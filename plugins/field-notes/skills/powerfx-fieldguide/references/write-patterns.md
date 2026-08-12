# Write Patterns

There is exactly one error-handling shape for a Dataverse write in Power Fx that actually
surfaces a failure to the user and doesn't lie about success. Every other shape that looks
reasonable — including the shape most people reach for first — is broken in a way that no
static checker catches, because the bug is only visible when the write actually fails against
real data (an alternate-key collision, a required-field miss, a plugin throwing).

## A compile-time trap first: `IfError`'s two arms must match type

`IfError(Patch(...), Notify(...))` doesn't compile at all — `Patch` and `Notify` return
different types, and `IfError`'s value and fallback arms must match. The fix that's usually
reached for is chaining a success `Notify` *after* the `Patch` so both arms of the outer
`IfError` end up Boolean. That fix is necessary, but on its own it isn't sufficient — see the
three shapes below, all of which chain something after the `Patch` and are all still broken at
runtime.

## The three broken shapes (all player-proven broken, 10 Aug 2026)

**1. `UpdateContext`-wrapped Patch.**

```
UpdateContext({v: Patch(MyTable, Defaults(MyTable), {...})});
IfError(..., Notify("Saved"), Notify("Save failed"))
```

A `Patch` failing *inside* an `UpdateContext({...})` call never reaches an `IfError` wrapped
around the surrounding statements — the failure is contained inside the `UpdateContext` call
and doesn't propagate the way a bare failing expression would. Result: a phantom "Saved" toast
fires and the row was never written.

**2. `With`-wrapped Patch.**

```
With({rec: Patch(MyTable, Defaults(MyTable), {...})}, ...)
```

Same failure mode, worse — the `With` shape doesn't just fail to propagate the error to an
outer `IfError`, it swallows the error entirely. Nothing downstream ever learns the write
failed.

**3. Bare chained `IfError`, patch-then-side-effects-then-notify all in one arm.**

```
IfError(
    Patch(MyTable, Defaults(MyTable), {...}); DoSomeSideEffect(); Notify("Saved", NotificationType.Success),
    Notify("Save failed", NotificationType.Error)
)
```

This looks like the natural single-call fix — put the Patch and its follow-up side effects in
`IfError`'s value arm, and the failure notification in the fallback arm. It still runs every
side effect listed after the failing `Patch` anyway: both the "Saved" and "Save failed" toasts
fire, and a dialog set to close on save closes even though nothing was written. Chaining
statements with `;` inside `IfError`'s value arm does not stop at the first failure the way you'd
expect.

## The capture pattern — the only shape that works

`IfError` wraps **only the write itself**, with a typed blank record (`LookUp(Table, false)`)
as its fallback — never anything after the write. Capture the result into a context variable,
then branch on whether the captured result carries a primary key. A successful write **always**
carries its primary key back; a failed one, captured this way, is the typed blank and its
primary key field reads as blank.

```
// The only shape that works (player-proven 10 Aug 2026):
UpdateContext({locResult: IfError(Patch(MyTable, Defaults(MyTable), {...}), LookUp(MyTable, false))});
If(IsBlank(locResult.'My Table ID'),
   UpdateContext({locErr: "Save failed — likely a duplicate key."}),
   Notify("Saved", NotificationType.Success); UpdateContext({locShowDialog: false}))
```

**Boolean variant for deletes** — a `Remove` has no record to capture, so capture a boolean
instead:

```
UpdateContext({locDeleteOk: IfError(Remove(MyTable, someRecord); true, false)});
If(locDeleteOk,
   Notify("Deleted", NotificationType.Success),
   UpdateContext({locErr: "Delete failed."}))
```

**Never call `Notify` inside the fallback expression of the `IfError`.** `FirstError` (or any
detail about *why* the write failed) is not reliably available at that point — write a static
failure message that names the most likely cause instead (e.g. "likely a duplicate key" for a
table with an alternate key), and put the `Notify` call in the branch that follows the capture,
not inside the `IfError` itself.

**The success test that makes this pattern work:** a successful Dataverse write always returns
a record carrying its primary key. So the branch condition is always
`IsBlank(result.'<Primary Key Display Name>')` — check the specific primary key field, not the
whole record (`IsBlank(record)` on a lookup/record value is unreliable — see the blank-record
family in `runtime-bombs.md`).

## Why this matters enough to sweep every write site

The three broken shapes all produce the same dangerous failure signature: a success toast fires
and/or a dialog closes even though the write failed, so the user has no reason to believe
anything went wrong. The capture pattern was race-tested in the player against real
alternate-key collisions (forcing a duplicate-key write to fail) and produced the correct
behavior: one error toast, the dialog stays open, no phantom success banner. Every write site in
an app should be converted to this pattern, not just the ones that happen to have been
player-tested against a failure case — a write site that's never been forced to fail is
unverified, by the same logic as any other runtime-only bug in this guide.

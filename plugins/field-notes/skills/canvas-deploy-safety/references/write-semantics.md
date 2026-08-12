# Write Semantics

What a canvas-authoring compile call's response does and doesn't tell you about what's actually
in the app, and how to find out for real.

## Validation status is not write status

**When a compile reports `Validation FAILED`, do not assume nothing was written — sync and diff
before trusting the app is unchanged, because a failed compile can write anyway.** Four
consecutive `FAILED` compiles in one session all applied their YAML: a throwaway custom property,
a broken column binding, and an experimental schema pin were all found sitting in live app state
afterward, none of them ever having appeared in a successful response. The service does not treat
"failed validation" and "don't write" as the same decision.

**When a compile reports zero errors and only delegation (or other) warnings, expect `FAILED`
anyway — warnings alone flip the status, and it still applies.** A run with zero errors and two
delegation warnings reported `Validation FAILED` and wrote its content just the same.

The rule this leaves you with: **the return value is diagnostic status, not write status, and the
two are independent.** The only way to know what is actually in the app is `sync_canvas` to a
scratch directory, followed by a diff — after **every** compile, whether it reported success,
failure, warnings, or nothing at all. Never sync into your working directory; it overwrites
same-named source files.

`(observed 4 Aug 2026)`

## Zero diagnostics is not "clean"

**When a compile returns zero diagnostics, do not read that as "this content is valid" until you
have proven the checker was actually looking — a dead or misconfigured session can return zero
diagnostics for reasons that have nothing to do with your content's correctness.** A run once
reported 93 errors — a whole class of otherwise-valid type names all "unrecognized," several
stock controls failing — that were entirely phantom, produced by a session that could not
actually validate anything; the identical files then validated with 2 real diagnostics once the
session was genuinely live.

**Confirm a checker is actually checking by injecting a deliberate error (a canary) and verifying
it gets reported.** If your canary isn't reported, the run wasn't a real validation and none of
its silence proves anything.

**Put the canary in a DIFFERENT file from whatever you're actually testing — a canary on the same
screen as your probe control can poison the rest of that screen's analysis and produce a false
"the probe is valid" reading.** This cost a real wrong conclusion once: a canary error and a probe
control were on the same screen; the canary's error was reported, the probe drew no diagnostic at
all, and the silence was read as "the probe passed." It hadn't — the canary's error had stopped
binding analysis for the rest of that screen, and the probe failed the moment it was tested alone.
A canary proves the session was live at the moment it fired; it proves nothing about siblings
downstream of it.

**A canary does NOT make a failing compile non-destructive — a deliberately-broken run still
writes whatever content it carries, canary included.** This was believed briefly and retracted the
same day: the reasoning was that a run "applies YAML only on full success," so a run designed to
fail was a free way to interrogate the compiler. It is not free — see "Validation status is not
write status" above. Never place an experiment in front of an app you care about, expecting a
failing result to roll it back. If a probe must not land for real, run it against a copy of the
app, or accept that you will need to clean up afterward and verify that cleanup by syncing.

## Dead sessions can write partial damage

**When a compile carrying new content reports "no active coauthoring designer session" (a dead
session), do not assume it wrote nothing — it can write a mutilated tree: the control structure
intact, but scores of value-carrying properties silently dropped (text, fill, colors, item
bindings, event handlers), rendering as blank or broken controls with no error anywhere.** The
earlier belief that a dead-session compile "writes nothing because it never reaches the service"
was wrong — it was based on dead probes whose content already matched the server, which are true
no-ops that only *look* like non-writes.

`(corrected 6 Aug 2026)`

Operational rules that follow from this:

- **Never compile new content against a session you haven't confirmed is live.** Probe pairing
  first with a harmless, **content-carrying** compile — a byte-identical (no-op) compile can
  never confirm liveness, because the service only performs the designer-session lookup when the
  payload differs from what's already stored, so a no-op probe always answers "live" regardless
  of whether a session is actually registered. See the pairing-protocol reference for the full
  null-test trap and escalation ladder.
- **After any dead-session compile that carried new content, sync and run a structural property
  diff** (names *and* values, not a text diff — the server reorders properties and elides
  defaults) before trusting anything about the resulting app state.
- **Repair via the whole-screen Studio paste** (delete the mutilated root container, select the
  screen, paste the authored children, save) — this path is pairing-independent and has restored
  fully mutilated screens byte-exact more than once. See `paste-deploy-pipeline.md`.

## Studio's client checker can lie after an external write

**When Studio's own Formulas/checker panel shows a cascade of "isn't recognized" errors right
after an external write landed (e.g. via the compile service), reload Studio before touching any
formula — the client can be showing a parse artifact of its own, not a real problem.** After one
externally-applied change to a named formula, Studio's client-side checker showed an
eleven-error cascade inside that one formula, every name in its body reported "isn't recognized,"
while both the compile service and the separate checker endpoint reported the change as clean. A
Studio reload (plus its usual re-registration delay) cleared every one of the phantom errors.

**Rule: when Studio's client-side checker and the service-side checker disagree, the service-side
result is the authority — reload the client rather than trusting or debugging against what it
shows.**

## Deploy paths and write semantics — additional facts

- A compile that returns a **phantom-error cascade** (hundreds of bogus errors naming unrelated,
  otherwise-valid identifiers) can still have written the real content underneath — "a fresh
  reconnect buys one guaranteed write" is not a rule you can rely on. An error reading like
  `Error while copying content to a stream` indicates a stale MCP-side session rather than a
  content problem; a fresh reconnect clears that specific error, but is not a general fix for
  every failure mode.
- **`sync_canvas` returning "no files" ("nothing written")** most often means the MCP's connect
  call happened while no Studio session had the app open, not that the app is empty. Protocol:
  open Studio in edit mode first, wait, connect, then sync.
- **The delete-then-recreate dance for forcing child order works via two separate compiles** —
  one without the reordered children, one with them present in the desired order — but the delete
  must be **sync-verified as actually landed** before you send the recreate; two dance compiles
  fired back-to-back can collapse into a single merge that never truly deletes anything, and the
  reorder silently fails. Even a verified fresh create can still rotate a container's leading
  children to the end in some cases; if the dance fails twice, switch to delete-by-compile
  followed by a Studio paste of the authored order — that restores order byte-exact.
- **After any batched round of formula-bar edits, sync and diff every touched property** — a
  per-edit "OK" is not proof an edit landed; one edit in a batch can silently fail to apply while
  every step in the batch reports success.
- **A diff tool that only compares property counts, not values, will miss real drift.** One such
  tool reported 14/14 components "ok" while the server actually held dozens of properties the
  authored source had never seen. Use a value-level diff (comparing actual property contents, not
  just how many properties exist) before any full-directory compile. When doing this: normalize
  whitespace before comparing (the server wraps long formulas differently than authored source),
  and be aware the server can emit a single scalar value as a multi-line block — any tool that
  copies "drifted" properties across must copy full line ranges, never a single line. Also be
  aware that a `Properties:`-only diff is blind to the control's declared **type** and its custom
  property declarations — adopting drifted property values onto a control whose declared type
  doesn't match the server's is not actually compile-valid, even though the property-level diff
  reports clean.
  `(A "FAILED compile still writes" is itself conditional, not absolute: two consecutive failed
  compiles — one live with real diagnostics, one dead with none — once left the server
  byte-identical to before either ran. Validation errors that abort *before* the merge step write
  nothing. Never assume either way for a given failure; sync and diff settles it every time.)`

## Studio only emits non-default properties

**When a synced-down component or screen looks nearly empty — a control reduced to little more
than its position — that's expected, not a sign of data loss: Studio only emits properties whose
value differs from the platform default.** A hand-inserted control round-trips through sync as
almost nothing at all, and a global app setting whose live value equals the platform default
never appears in synced source either. Absence of a property in synced YAML means "this equals
the platform default," never "this was unset" and never "this property is unsupported."

**Corollary: never diff synced YAML against authored YAML to check whether an edit applied — read
the value in Studio's Advanced properties pane instead.** Six spacing properties were once pasted
into a container and none of them appeared in the subsequent sync, which looked like the paste had
failed; the Advanced pane showed every one of the six holding exactly the authored value. The
paste had worked; the synced YAML simply omits anything equal to a computed or default value, and
is not a reliable place to check "did this land."

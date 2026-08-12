# Runtime Bombs

Formulas that compile clean, pass App Checker, and show zero errors in Studio's own checker —
and then fail the moment they actually execute against real data, either by throwing at
runtime or by rendering blank with no diagnostic anywhere. Static analysis type-checks a
formula; none of these bugs are type errors.

## `Value(<choice>)` fails at runtime

**Symptom:** `Value(<choice>)` throws *"We cannot convert the value to a number because the
value is not a string"* at runtime, even when the argument is a member constant like
`Value(MyChoice.Accepted)` — something that looks like it should be a compile-time constant.
This broke every formula built on a choice→number bridge, all of which had compiled clean and
passed App Checker.

**Rule:** never call `Value()` on a choice column or a choice member anywhere that will
actually execute. Replace the bridge with named-formula integer constants that mirror the
choice's real stored option values (read them off the choice's metadata — don't guess), plus a
`Switch` on member **equality**:

```
Status_Draft = 100000000;
Status_Approved = 100000001;
Status_Rejected = 100000002;

StatusToInt(s: OptionSetValue): Number =
    Switch(s, MyChoice.Draft, Status_Draft,
              MyChoice.Approved, Status_Approved,
              MyChoice.Rejected, Status_Rejected);
```

Member equality (`s = MyChoice.Approved`) is the one universally supported operation on a
choice; `Value()` on it is not, no matter how the argument is spelled.

`(player-proven 5 Aug 2026)` — five formulas were converted to this pattern in one sitting and
compiled clean, but none had a live caller yet at that point. Treat a constants+Switch
conversion as **unverified**, not "fixed," until a screen actually calls it and you've watched
it render correctly in the player — a compile-clean UDF with no caller has not been executed by
anything, static or otherwise.

**Diagnosis pattern that worked:** three probe Text labels on a scratch screen (`scr_Example`),
one per link in the suspect call chain, with the broken `Value(member)` call kept in place
briefly as a negative control — if the probe harness itself doesn't surface the known-bad call
as broken, the harness isn't proving anything about the rest of the chain either.

## Explicit Column Selection silently blanks lookup navigation

**Symptom:** `record.'Lookup Column'.'Some Field'` inside a UDF, and `ThisItem.'Lookup
Column'.SomeField` inside a grid column, both return `Blank()` at runtime with zero errors
anywhere. A helper function that counts or reads through the relationship silently returns
nothing, and a grid column bound the same way renders empty.

**Why filters on the same relationship keep working:** a filter predicate over the relationship
compiles to a server-side join and is unaffected — only *navigation reads* through the lookup
are blanked. This is what makes the bug so easy to miss: the query that populates a list works
fine; only the column that displays a related field through it comes back empty.

**Not fixed by:** refreshing or reconnecting the data source, republishing, or reconnecting the
client.

**Fix:** Settings → Updates → **"Disable explicit column selection" → On** (the toggle's name
is inverted — turning it *on* disables ECS), then close and reopen the app.

**Trade-off:** disabling ECS trades a larger network payload (every lookup's shadow columns are
now fetched unconditionally) for correctness. It's the right call when every table involved is
small; revisit if row volumes grow enough that the fatter payload becomes the bigger problem.

`(root-caused 5 Aug 2026)`

## The rest of the catalog

- **A parenthesized `;` chain inside a `Switch` arm compiles clean and silently never runs**
  (player-proven). Unparenthesized `;` chains as the top-level body of a `Switch` or `If` arm
  are player-proven fine — the failure is specific to the parenthesized-chain-as-one-arm shape
  inside `Switch`. The safe universal shape either way: write single-call arms inside
  `Switch`/`If`, and chain any follow-up side effects *after* the `Switch`/`If` expression, not
  inside one of its arms.

- **The blank-record family** — four related traps, all silent:
  - A blank record passed as a record-typed UDF argument kills the calling expression with no
    error.
  - Reading a primary key off a combo box's `.Selected` at the call site (e.g.
    `cmb.Selected.'Some ID'`) throws a 400 with a schema-cased-property error when nothing is
    selected yet.
  - `lookup.PK = Blank()` in a filter predicate dies silently; `IsBlank(lookup)` on a whole
    lookup record also 400s. Only `IsBlank(lookup.PK)` works.
  - Guard: branch on `IsBlank(cmb.Selected)` at call sites before reading anything off the
    selection. A blank record used as the *value written into* a Patch's lookup field is fine —
    the trap is only in reading, not in writing.

- **A `DefaultSelectedItems`-produced `.Selected` leaves dependent primary-key reads dead**
  until a real user click happens — the default selection populates the control visually but
  not in a way that downstream `.Selected.PK` reads can see. Fix: hoist the record into a
  context variable (`OnVisible`: `UpdateContext({locSel: First(...)})`; `OnChange`: update the
  same variable) and reference only the variable in every formula that needs the PK, never the
  control's `.Selected` directly.

- **`[@'Name']` shadowing.** When a global choice and a column on the record being filtered
  share the same display name, the record scope inside `Filter()`/`ForAll()` shadows the
  global — a bare `'Shared Name'.SomeMember` binds to the *column*, not the choice, and fails.
  Force global resolution with `[@'Shared Name'].SomeMember`. This bit the same app five
  separate times with five different display names — check for a same-named column every time
  a choice member reference misbehaves inside a record scope.

- **`ItemDisplayText` and grid-column `Text` formulas run a restricted function whitelist.**
  Plain field access, one-hop lookup navigation, `If`, and `&` all evaluate. UDFs, `Coalesce`,
  `LookUp`, and `Concat` all render blank with **zero diagnostics** — no error, no warning, just
  an empty cell. A cell that needs a table function is impossible to build directly in a grid;
  use a gallery instead, or denormalize the value onto the row so the cell needs only plain
  field access.

- **A create-`Patch` that includes a status/state field silently no-ops the *entire* Patch** —
  you get a success toast and nothing is written, with no error anywhere. Never write a
  status/state field on create; write it in a second, separate `Patch` call, and only in edit
  mode.

- **`Navigate()` is rejected inside `OnVisible`.** Guard screen-level redirects with a Visible
  state on a container instead of calling `Navigate()` directly from `OnVisible`.

- **An unset date picker defaults to today**, not blank. Always author its default explicitly
  as `DefaultDate: =Blank()`, or every save that doesn't touch the field silently stamps
  today's date into it.

- **Dialog text inputs need a delayed trigger output** (`TriggerOutput: =TriggerOutput.Delayed`
  — the modern-control equivalent of the older "delay output" property some docs still name
  differently) or any enable-guard reading the input's value only reacts after the field loses
  focus, not as the user types.

- **Use `gallery.AllItemsCount` instead of `CountRows(gallery.AllItems)`** for a running count.

- **`ButtonAppearance.Transparent` renders as a visible white pill in the player**, not an
  invisible hit target and not a link-styled button. For an invisible tap target or a
  link-look button, use a classic button control with a transparent fill instead — it has no
  accessible-label requirement blocking that use. Also: a modern `Text` control has no
  `OnSelect` and does not forward clicks to its enclosing gallery template — a row-open
  interaction needs a real button, not a styled label.

- **`Table(t1, t2, t3)` is the sanctioned way to union multiple tables inside App.Formulas** —
  an `Ungroup(Table({...}))`-style construction does not compile there. Watch for field names
  in a table literal that collide with parser keywords (a field literally named `End` hit the
  same parse error) — avoid reserved-sounding field names in table literals passed through
  App.Formulas.

- **UDF and type constraints:**
  - `Type(RecordOf(MyTable))` excludes rollup columns from the record type — adding a rollup
    to a table breaks every record-typed UDF parameter over that table. Convert the parameter
    to a GUID.
  - A UDF cannot return `Type(RecordOf(X))` when X has an N:N relationship column — the actual
    returned record carries an extra field the declared type doesn't have, and it must be a
    strict subset. Return a scalar instead.
  - `Set(v, Blank())` leaves a variable untyped and fails compilation. Use
    `LookUp(SomeTable, false)` to get a typed blank record instead.

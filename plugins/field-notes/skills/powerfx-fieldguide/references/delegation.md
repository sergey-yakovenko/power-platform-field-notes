# Delegation

A delegation warning is a symptom, not the problem. The actual constraint is schema shape —
which hop of a lookup chain you're comparing, whether a column exists locally or two hops
away, whether the value you're testing is a choice or an already-converted number. Fix the
schema or the shape of the query; don't chase the warning with formula tricks.

## One hop to a primary key delegates. Record equality does not compile

**Symptom:** `SomeTable = someRecordVariable` looks like the natural simplification of
`SomeTable.'Display Name Of PK' = someRecordVariable.'Display Name Of PK'`, but it fails to
type-check at all — `Incompatible types for comparison` — while the "verbose" version
delegates cleanly.

**Why:** two facts decide this, and neither is visible in the formula text — you have to check
metadata:

| Table | Primary key logical name | Its **display name** |
|---|---|---|
| `MyTable` | `mytableid` | e.g. `Project` |
| `MyOtherTable` | `myothertableid` | e.g. `Gate` |

A table's primary-key column is displayed under a friendly name (often the table's own name, or
close to it) that gives no visual hint it's the row's own GUID. So `someRecord.'Project'` is a
**GUID, not a name** — comparing `SomeTable.'Project' = someRecord.'Project'` compiles to a
one-hop `_mytableid_value eq <guid>` filter, which is natively delegable.

`SomeTable = someRecord` is *not* a shorthand for that comparison — a
`Type(RecordOf(SomeTable))`-typed parameter is a distinct nominal type from the lookup's own
record type, so the two never type-check as equal in the first place, regardless of delegation.

**Rule:** always compare through the display name of the primary key column explicitly. Before
writing a lookup-record comparison, check the table's primary-key display name in metadata
rather than assuming it matches the table name.

## Two hops through a lookup are unfixable in Power Fx — denormalize

**Symptom:** `'Child Table'.ParentLookup.'Grandparent Display Field'` — reaching two hops
through a chain of lookups — never delegates, however it's rewritten. There is no Power Fx
construction that makes a two-hop lookup traversal delegable.

**Fix:** add the far column directly onto the table that's two hops away from it (a new lookup
or a copied scalar column, whichever is appropriate), backfill it, and compare one hop instead
of two: `'Child Table'.'Denormalized Column' = someValue`.

**The cost that's easy to forget:** a denormalized column has no automatic producer. Something
— a business rule, a plugin, a real-time workflow — must set it on create and on update, or the
column silently goes blank on new rows and drops them out of every count and filter that
depends on it. Adding the column is half the fix; wiring something to maintain it is the other
half, and it's easy to ship the first half and forget the second.

A new column is invisible to the app's Power Fx until the data source is refreshed in the Data
pane — a formula that names it and fails with `'Column' isn't recognized` almost always means
"refresh the data source," not "the column doesn't exist."

## Compare a choice to a choice member, never `Value()`, in a predicate

**Symptom:** `Value(choiceColumn) = 3` seems like the obvious way to filter on a choice's
underlying integer, but a choice is not a valid parameter type for a UDF, so a single
parameterized filter function (`RowsWithStatus(t, status: Number)`) can't accept a choice
argument cleanly, and calling `Value()` inside the filter predicate itself blocks delegation.

**Rule:** compare the choice column directly to a choice member —
`'Status Column' = MyChoice.Approved` — which compiles to a native equality filter on the
stored integer server-side. Because a choice can't be passed as a UDF parameter, this means
**one function per status value** (`RowsApproved(t)`, `RowsRejected(t)`, ...) rather than one
parameterized function. `Value()` is fine to call on an already-fetched record outside a filter
predicate — the restriction is specifically on predicates that need to delegate.

Also: pull any UDF call *outside* the predicate you're filtering with (`With({x: SomeUdf(...)},
Filter(t, ... x ...))` rather than calling the UDF inside the `Filter` condition), and sort on a
column local to the table being sorted — sorting through a lookup (`Sort(t,
'SomeLookup'.SomeField)`) is exactly as non-delegable as filtering through one.

## `[@'Name']` when a choice and a column share a display name

Inside `Filter()`/`ForAll()`, the record scope shadows an identically-named global choice — a
bare `'Shared Name'.Member` inside the predicate binds to the record's *column*, not the
global choice, and fails. Force the global with `[@'Shared Name'].Member`. A choice reference
only escapes this by accident, when it happens not to share its display name with any column
on the table being filtered — the underlying construct is identical either way, so treat every
choice-member reference inside a record scope as at risk until you've checked for a same-named
column.

If a filter needs to compare a text-converted choice against a parameter (`Text('Shared Name')
= someParam`), that has the same non-delegation problem as the `Value()` case above — split
into one function per option value instead of trying to parameterize it, especially when the
choice only has a couple of options.

## Feeding a list: the projection ruling

There are three ways to shape a Dataverse table before binding it to something that renders a
list, and they are **not interchangeable** — choose per table, by row count and by what the
consuming control needs:

| Shape | Delegable | Can rename/compute a field | Server sort + paging | Reaches choice labels |
|---|---|---|---|---|
| raw (the data source itself, or `Filter`/`Sort`/`Search`/`LookUp` over it) | yes | no | yes | only if the consuming control resolves them itself |
| `ShowColumns(...)` / `AddColumns(...)` / `RenameColumns(...)` | **no** | no (`ShowColumns`) / yes (`AddColumns`) | **no** | only if the consuming control resolves them itself |
| `ForAll(t As r, {...})` | **no** | yes | **no** | yes — resolve with `Text(r.'Choice Column')` inside the projection |

**`ShowColumns`/`AddColumns`/`RenameColumns` are NOT delegable** — they're in the same
non-delegation class as `ForAll`. The underlying documentation states this outright, and
further notes that the *output* of these shaping functions is subject to the non-delegation row
cap (roughly 500, at most 2000) once it's materialized locally. The inner `Filter`/`Sort` still
delegates server-side; it's the shaping wrapper around it that forces local materialization and
the cap. Note this corrects an earlier, wrong belief that `ShowColumns` was "just trimming
payload" and therefore harmless for delegation — it is not `(corrected 5 Aug 2026)`.

**So the only genuinely delegable shape for feeding a list is raw** — no shaping wrapper of any
kind. This collides with any control that requires a `RecordKey`-style column to exist directly
in the bound table (see `pcf-kit-bindings` for that contract) — producing that column is itself
a shaping operation, so a table that needs one can't simultaneously be delegable through a
projection. Where that matters, the workaround is a **pinned, typed component/control property
bound to the raw table** rather than a Power Fx projection — the projection step is skipped
entirely instead of being made delegable.

**Ruling that generalizes:** use `ForAll` freely for genuinely bounded, small tables (a
handful to a few dozen rows); keep the big, potentially-large tables that your zero-delegation
gate actually cares about strictly raw. Decide and record this per table once, rather than
re-deciding it ad hoc at every screen that lists it.

**Absence of a delegation warning proves nothing.** The platform's own guidance is explicit
that a warning "often appears... but not every non-delegable case shows this warning." To
actually surface it: set the app's data row limit to 1 (Settings → General), compare
`CountRows(shapedVersion)` against `CountRows(rawVersion)` — they'll diverge if shaping broke
delegation — and confirm on the wire (a network monitor) that a genuinely delegated feed shows
server-side paging parameters, not a full unpaged fetch.

**Two consequences of `ForAll` shaping that are easy to miss:**

- **Automatic sorting dies.** A directly-bound Dataverse dataset on a data-grid-style control
  sorts server-side for free; once the table is `ForAll`-projected first, any "sortable" column
  needs its own `OnChange` handling to actually re-sort, because the automatic sort/page
  outputs only apply to a direct binding.
- **It's the only way to reach per-cell color/tag styling** on controls whose cell-coloring
  properties name columns that must exist *in the bound dataset itself* — those colors (as hex
  strings) have to be computed into the row during the `ForAll` projection; a raw binding has
  no way to inject a computed color column.

**Choice columns have a hidden label twin that Power Fx can't see through a schema query.**
Every Dataverse choice column has a companion "formatted value" virtual attribute holding its
display label, and that companion attribute is **absent from a Power-Fx-visible schema query**
— so `ShowColumns` can't name it, and any projection built from a schema listing silently drops
it. This makes `ShowColumns` and native choice-label rendering close to mutually exclusive,
which is a second, independent reason to prefer `ForAll` with an explicit
`Text(r.'Choice Column')` resolution — that reads the label in Power Fx directly and sidesteps
the missing-attribute problem entirely. Whether a given list-rendering control resolves choice
labels itself when bound raw, or needs them resolved for it, is worth confirming per control
rather than assumed either way.

## Delegation refinements (grab-bag)

- A field read off a **`With()`-scope record** inside a filter predicate is flagged
  non-delegable; the same field read off a **context variable** (set via `UpdateContext`, then
  referenced) is not. Prefer `UpdateContext` + read over `With()` when the value feeds a
  predicate that needs to delegate.
- **A UDF call inside a `Filter` predicate is itself non-delegable**, independent of whatever
  the UDF does internally — pull it out with `With()` outside the predicate instead (see above
  for choice comparisons).
- **`With()` kills `StartsWith` delegation** — a `StartsWith` call that would otherwise delegate
  stops delegating once it's evaluated inside a `With()` scope.
- **`choice = Blank()` delegates; `IsBlank(col)` does not**, for a choice column specifically.
  Prefer the `= Blank()` form in a predicate that needs to delegate over an otherwise-equivalent
  `IsBlank()` call.

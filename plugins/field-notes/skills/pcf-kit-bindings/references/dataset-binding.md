# Dataset Binding

The full manifest-verified rule set for getting real data through a PCF dataset or a Table
custom property, and how to tell which of three near-identical-looking failures you're looking
at when a control renders blank or wrong.

## Reading the manifest

`describe_control` 404s on any PCF/code component — it only covers stock and modern controls.
The real contract for a code component is its manifest:

```bash
dataverse api request --target dataverse \
  --path "api/data/v9.2/customcontrols?\$filter=name eq '<component-name>'&\$select=manifest"
```

The manifest distinguishes an ordinary bindable `property` from a `property-set` on a dataset —
and that distinction, not guessing at control properties, is what settles most binding questions.
Example manifest shape for a dataset's bound property-sets:

```
=== property-set (dataset column bindings) ===
  RecordKey            SingleLine.Text   bound   false
  RecordCanSelect      TwoOptions        bound   false
  RecordSelected       TwoOptions        bound   false
  ColDisplayName       SingleLine.Text   bound   true
  ColName               SingleLine.Text  bound   true
  ...
```

`bound   true` on a required column-binding property-set means it is `required="true"` in the
manifest and must be supplied even if a public control-facing doc lists fewer required fields —
the manifest is authoritative for *this installed version*, and a doc page can describe a newer
release than what's actually deployed. Check `ColCellType`-style enumerated properties against
the manifest's own accepted member list too — a plausible-looking string that isn't an actual
enum member (e.g. a generic "text" cell type when the real member set is a fixed short list) is
silently accepted or rejected depending on the property, so verify rather than assume.

## Dataset binding rules, assembled from repeated failures

1. **A code component's first dataset always binds as `Items`**, regardless of what the manifest
   calls it internally. `records`, `items`, and `Personas` have all been observed to surface as
   plain `Items` — using the manifest's own internal name for the *first* dataset produces an
   unknown-property compile error.
2. **A second dataset binds as `<manifestDatasetName>_Items`.** A manifest dataset internally
   named `columns` persists in the canvas app as `columns_Items`, even when Studio's own property
   picker UI labels the same property with a friendlier display name (e.g. "Columns"). Only the
   *first* dataset gets the special "just `Items`" treatment; every dataset after that keeps its
   manifest name with `_Items` appended.
3. **Datasets bind by column name, and a wrong name renders nothing and raises no error.** This
   is the most expensive failure mode in this whole area, because it produces no diagnostic
   anywhere — not at compile time, not in App Checker, not at runtime. If a control renders empty
   or a specific field is missing, re-verify every column name against the manifest before
   assuming anything else is wrong.
4. **Choice/picklist columns have a hidden label twin that a schema tool may not surface.** A
   Dataverse picklist typically has a matching virtual "label" attribute alongside the raw value
   column; that virtual attribute can be absent from a generic schema-introspection call, so a
   projection built purely off that schema silently drops the label column. Confirm directly
   against the table's live attribute list, not just a cached schema dump, when a choice column's
   label isn't showing up where expected.

## `RecordKey` is a COLUMN in your data, not a control property

The single most common wrong turn: trying to set `RecordKey` (or `RecordCanSelect` /
`RecordSelected`) as a property on the control itself. The manifest is explicit that these are
**bound property-sets on the dataset**, exactly the same mechanism as `ColName` /
`ColDisplayName` on a columns dataset — they bind by **matching a column name in the table you
hand to `Items`**, not by being assigned a value in the properties pane.

The fix, once this clicks, is a one-line change: add a column literally named `RecordKey` to the
projection/table passed into the dataset property. Nothing else needs to change.

Compiler error messages here are a direct, literal description of the missing column, not a
malformed-property complaint:

```
RecordKey: =cmpX.RecordKey        ->  Property reference isn't valid
RecordKey: ="Key"                 ->  The specified column 'Key' does not exist
```

*"The specified column"* is the compiler telling you, twice, that this is a missing-column
problem, not a bad-property-value problem — several failed attempts were spent trying to fix this
as a control property before the manifest was actually consulted.

**Without a `RecordKey` column, `EventRowKey` (or the equivalent row-identity output) degrades to
a row ordinal** — the first row reports `1`, the second `2`, and so on — so any downstream
`LookUp` keyed on that value silently resolves the wrong row or nothing at all. Add `RecordKey` to
the per-table checklist for every list-style dataset binding, alongside the column-definitions
property.

`RecordCanSelect` / `RecordSelected` work the identical way and are how you drive a
programmatic-selection input event on the control (when the control documents one).

**A selection-mode property that is `required="true"` in the manifest may still not need
setting** — it can carry a manifest `default-value` (e.g. defaulting to single-selection), in
which case the selection output populates correctly with no explicit binding at all. Check the
manifest's `default-value` before assuming a required property must be authored.

## The Table-property schema rule — the Default IS the type

Proven experimentally against a live table (4 Aug 2026), comparing three `Default` shapes for the
same Table custom property, all fed the exact same real caller data:

| `Default` | Caller passes real rows | Result |
|---|---|---|
| `=Table({SomeSampleField: "…"})` — a schema that doesn't match the real table | the real table | **rejected** — "the table passed in has none of the expected columns" |
| `=Table({realcolumnname: ""})` — one real column, wrong shape otherwise | the real table | **rejected**, naming that specific column |
| `=Table()` — empty schema | the real table | **accepted**, row count is correct, but **every field on every row is stripped** |

The reasoning that explains all three rows: an empty schema type-checks against literally
anything, *because it has no columns to conflict with* — and for that exact same reason it
carries zero columns across the property boundary. A type check that can never fail is not
evidence that the binding is doing anything useful.

**Two Table properties on the same component do not necessarily want the same treatment:**

- A **column-definitions** property (naming which fields to render, how wide, sort behavior,
  etc.) should be **pinned to the full union of every field any caller uses** — its shape is
  typically identical across every calling surface, so pinning costs nothing, and *any* field
  used by *any* caller but missing from the pinned Default is silently dropped for every caller,
  not just the one that needed it. A real regression here: an eight-field pin was missing three
  fields that different callers separately relied on (a "show as sub-text of" association, a
  sort-by override, and a resizable flag) — those callers rendered with no headers/sub-text at
  all and no error anywhere.
- A **raw row-data** property (the actual `Items` feed) is the one where the "just leave it
  schema-free" instinct is the trap described above — an empty schema here is confirmed to strip
  every field, not just to be "unverified as risky."

**The proven pin pattern:**

```yaml
Items:
  PropertyKind: Input
  DataType: Table
  Default: =FirstN(<DataSource>, 0)     # zero rows; static type = the real row type
```

This is **proven**, not merely hoped for — a Table property's `Default` may reference a live data
source, and doing so type-pins the property to that table's real, current column set with no
hand-typed column list to get wrong or let drift. If a particular authoring surface rejects a
data-source reference in a `Default` (unconfirmed to occur, but not yet proven impossible in
every tool), fall back to `=Filter(<DataSource>, false)`, and only as a last resort a fully
hand-typed literal record shape — which needs a real typed lookup (e.g.
`LookUp(<DataSource>, false).<ChoiceColumn>`) to get a correctly-typed *blank* choice value,
since a bare literal can't express one.

## An empty `Items` type is why the control shows no fields at all (5 Aug 2026)

Root-caused in one step, confirmed by the compiler itself: with an empty-schema `Default` on the
`Items` property, a formula referencing a field of `First(<component>.Items)` — evaluated
*inside* the component, before any real data is even in play — is rejected at author time with an
unrecognized-name error. That is the compiler proving the type carries no columns, independent of
any runtime data at all.

The manifest explains the rest: a primary records dataset typically declares **no property-set
for the actual data columns** — only identity/selection property-sets like `RecordKey`,
`RecordCanSelect`, `RecordSelected`. So the control resolves each configured column name (e.g.
each `ColName` in a columns definition) against the dataset's *column metadata*, and that
metadata comes from the **static type of whatever is bound to `Items`**. An empty static type
means there is nothing to resolve any configured column name against — pinning the type (above)
is the entire fix.

**The field-selection picker some hosts offer when a dataset is placed directly on a screen is a
red herring inside a component, and chasing it wastes time.** Microsoft's own documentation notes
that field selection applies only to a control's **primary** dataset. A *secondary* dataset (like
a columns-definition dataset) never gets a picker regardless of whether it's inside a component —
that's normal, not a defect, and pinning its type is unaffected by whether a picker exists.
Concretely: a correctly pinned, correctly rendering columns-definition property is proof by
itself that a PCF dataset can receive working column metadata across a component boundary from
the declared static type alone, with no field-selection UI involved anywhere in the chain. Don't
treat "no picker inside the component" as a signal that something is broken.

## Diagnose at the boundary — read the empty state, not the checker

**The App Checker / compiler will report zero errors in every one of the following three
distinct failure states**, because in each case the type check that would need to fail, can't.
Live instrumentation at the property boundary (e.g. a visibility condition tied to
`CountRows(<component>.Items) = 0`, wired to an empty-state placeholder) is what actually
distinguishes them:

| Symptom | Cause |
|---|---|
| The empty-state placeholder shows even though real rows exist | **rows erased** — the Items Default has an incompatible/empty schema and the whole row is being rejected upstream, not just fields |
| No empty-state placeholder, real row count, but no column headers at all | **columns erased** — an empty-schema `Default` stripped every field; pin the type |
| Headers render, but one specific cell is always blank | **a single wrong `ColName`** — re-check that one field's name against the manifest/data, everything else is fine |

Treat "App Checker: zero errors" as uninformative here — it is true in all three rows above, so
it cannot be used to distinguish or rule out any of them.

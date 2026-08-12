# Canvas Schema Sync

How a canvas app's view of Dataverse schema falls out of sync with the real schema, and the
escalation ladder for getting it back in sync. Once the app-side schema is settled, hand the
compile itself over to `canvas-deploy-safety`.

## A new column is invisible until the data source is refreshed

**When a formula referencing a column you just added in Dataverse fails with
`'<column>' isn't recognized`, the column almost certainly exists fine — the app's data source
just hasn't been refreshed to see it.** Refresh the data source (Data pane → the source's menu →
Refresh) before debugging the formula itself. This is the first, cheapest rung of the escalation
ladder below — most schema-sync problems stop here.

## When refresh alone doesn't fix it: the escalation ladder

**When a relationship or column change produces an error like "unexpected additional field" on a
UDF or record-typed call, and a schema-inspection tool confirms the column *is* there, refresh
alone can fail to fix it — even a saved refresh, even after a full close and reopen of the
authoring session.** The underlying reason: the app compiler resolves record types and UDF return
types against the app **document's own stored schema snapshot**, which is a separate thing from
the live session's schema view. A plain Data-pane refresh updates the live session's view but does
not always update the document's stored snapshot for every kind of change — a new relationship
touching a record type used in a UDF signature is one case observed to need more than refresh.

**The escalation ladder for "unexpected additional field" (or a similarly stuck-stale schema
error) after any relationship change:**

1. Refresh the data source(s) on both ends of the relationship.
2. Save the app.
3. If still stuck: **remove and re-add both data sources involved**, then save. This is the step
   that actually resolves a stuck stored-schema snapshot when refresh doesn't.

**Rebuilding a data source this way can also surface a latent, previously-masked defect** — a
stale schema snapshot can hide a bug in a formula that referenced the source, because the compiler
was checking against outdated field information the whole time. Treat a remove/re-add as an
opportunity to re-verify formulas touching that source, not just a mechanical unstick.

## Renaming a table doesn't rename the data source

**When you rename a table in Dataverse and the app keeps failing to resolve columns on it (or
keeps resolving to the pre-rename identifier), remember that a canvas app captures a data source's
name at the moment it's added, not live from the table's current name.** Renaming the underlying
table afterward does not update the app's data source, and refreshing does not fix it either — the
data source entry has to be **removed and re-added** for the app to pick up the new name.

**Power Fx identifiers are case-sensitive**, so even a single-character case difference between
what's authored and what the data source is actually named will fail to resolve — don't assume a
resolution failure is a naming mismatch in the display name when it could be a case mismatch in an
otherwise-correct name.

## Choice columns have an invisible label twin

**When you need a choice/picklist column's human-readable label rather than its raw stored value,
and a schema-inspection call doesn't list any column that looks like it holds the label, that's
expected — the label lives on a virtual attribute that schema-introspection tools don't surface.**
Every Dataverse choice (picklist) column has a matching virtual attribute holding its formatted
label (conventionally the choice column's logical name with a `name`-style suffix). These virtual
label columns are **absent from schema-introspection results**, so any technique that names
columns explicitly from an introspected schema (a column-projection/shaping function, for example)
cannot name them and will silently drop them from its output.

**Prefer resolving the label in Power Fx itself** (referencing the choice column's *display* text
directly in the formula, rather than trying to carry a raw picklist value and format it
downstream) over trying to project a virtual label column by name — the virtual column not
appearing in the schema makes the by-name approach fragile in a way that resolving the label
inline isn't.

## What comes next

Once a relationship or column change is confirmed synced on the app side (ladder above complete,
formulas re-verified against the rebuilt data source), the compile that deploys those formula
changes has its own set of write-safety rules — see **`canvas-deploy-safety`** for what a compile
does and doesn't guarantee about what actually lands in the app.

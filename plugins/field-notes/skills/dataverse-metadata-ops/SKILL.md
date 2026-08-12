---
name: dataverse-metadata-ops
version: 0.1.0
description: Hard-won safety rules for changing Dataverse schema - tables, columns, relationships, alternate keys - and for writing migration scripts against the Web API. USE WHEN creating or altering Dataverse metadata, adding lookups or alternate keys, choosing delete behaviors, scripting schema waves, or when a canvas app stops recognizing a column after a schema change. DO NOT USE WHEN only querying data (the stock dv-query skill covers that) or authoring canvas YAML.
author: Sergey Yakovenko
---

# Dataverse Metadata Ops

Dataverse schema changes look like ordinary API calls that either succeed or fail. Several of
them do neither cleanly: an update can report `200 OK` and never actually stick, a key can exist
and enforce nothing, and a perfectly legal lookup can quietly break every other table's ability to
read through it. Treat schema authoring as a procedure with a read-back verification step, not a
single write you trust the response of.

## 1. Recreate, not repair

**When a metadata update reports success but the value never shows up on read-back — most often
an empty display label after batch-creating several relationships back to back — stop retrying the
update and drop-then-recreate instead.** A wedged label was hit with four different PUT variants
(solution-context toggled on and off, a dedicated merge-labels action, a minimal typed body) plus
a full publish, and every one of them reported OK and read back empty. The fix that actually
worked: drop the relationship (and any alternate key sitting on the column first), then re-run the
same idempotent create script — labels commit fine at create time, and a backfill step repoints
any rows that need it. **Verify labels after any batch relationship creation**, not just the one
that seemed to misbehave: read `Attributes(...)?$select=DisplayName` and confirm
`LocalizedLabels` is non-empty for every relationship created in that batch, not only the last one
— only the first of several back-to-back creates kept its label in the case that surfaced this.
`(four PUT variants + a full publish, all no-ops, 5 Aug 2026)`

## 2. Alternate keys: activation is async, and null bypasses it

**When an alternate key was "just created" and duplicate rows aren't being rejected, don't
conclude the key is broken — poll its status instead of trusting presence in the maker portal.**
Key creation is asynchronous: it can sit `Pending` for around 50 seconds before flipping to
`Active`, and a `Pending` key enforces nothing while looking fully present everywhere you'd check
it by eye. Always poll to `Active` before relying on it.

**Separately: an alternate key stops enforcing uniqueness the moment any key column is null.**
This cuts both ways — sometimes it's the bug (a client can silently write a colliding null-keyed
row), sometimes it's exactly what you want (legacy rows with an unset key column can coexist
peacefully with newly-enforced, fully-keyed rows on the same table, letting you land a key without
a destructive backfill of every historical row first). Decide which case you're in before treating
null-bypass as a defect to fix.

## 3. Relationship limits and delete behavior

**A table can have only one parental (Cascade) relationship — a second attempt fails with error
`0x80047007`.** If a child table already cascades from one parent, every other parent lookup on it
must use a non-cascading behavior (typically Restrict), no matter how natural Cascade would read
for that second relationship.

**Delete behavior is a compliance decision, not a default to leave alone.** The platform default
(`RemoveLink`/no-restrict) silently orphans child records instead of blocking the delete — audit
every new relationship's delete behavior explicitly rather than accepting whatever the create call
defaulted to. A full sweep of relationships that had never been reviewed found **all of them**
sitting on the wrong behavior — every one would have let deleting a parent orphan its children
instead of blocking, until each was set deliberately (Restrict where a record is compliance
evidence, Cascade where it's disposable operational detail).

## 4. The virtual-table lookup rule

**When list/detail screens that read through a particular lookup hang on a spinner while
aggregate counts on the exact same data keep working fine, suspect a lookup that targets a virtual
table.** Never add a lookup whose target is a virtual table (e.g. a directory-backed identity
table) to any table that other tables `$expand` into. Selecting that lookup inside a server-side
`$expand` fails (SQL error 207 — the join references a shadow column that doesn't exist in SQL for
a virtual-target lookup); top-level selects on the same column work fine, which is exactly what
hides the problem until something downstream tries to expand through it. Aggregate queries
(`$apply`/aggregate) also keep working, so **a correct caption is not a working register** — don't
let a passing count convince you the underlying read path is healthy. `(API-proven 10 Aug 2026)`

See `references/metadata-traps.md` for the full trap list, including the identity-vs-contact
column pattern that lets you keep a directory-backed identity lookup without poisoning every other
table's reads through it.

## 5. Migration scripts are idempotent waves

Every schema-changing script should be safe to run twice: confirm the target environment before
any write (a multi-environment tenant's default CLI profile can silently point somewhere other
than where you intend), never trust an "OK" response without a read-back check, and respect
existing delete-behavior constraints by ordering writes so children are created/updated before the
parents that Restrict against them. See `references/migration-script-pattern.md` for the concrete
pattern (wave numbering, backfill + repoint, go/no-go read-back) and the toolchain gotchas that
bite these scripts specifically.

## 6. After any relationship change

A new or changed relationship or column is invisible to a canvas app until its data source is
refreshed, and refresh alone doesn't always fix it — see `references/canvas-schema-sync.md` for
the refresh-to-remove/re-add escalation ladder. Once the schema side is settled and you're ready
to compile the app against it, hand off to **`canvas-deploy-safety`** for the write-safety rules
around that compile.

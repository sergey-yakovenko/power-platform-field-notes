# Metadata Traps

Specific Dataverse metadata behaviors that don't match what the API response — or the maker
portal — appears to be telling you.

## Display labels can wedge, and only recreation fixes them

**When several lookups are created back-to-back in one batch and only the first one keeps a
working display label, don't keep retrying the update on the broken ones — they're wedged, not
slow.** In one batch of three relationships created in sequence, only the first kept its label;
the other two ended up with a genuinely empty label set, which reads in Power Fx as
`'<Display Name>' isn't recognized` even though the underlying column works fine and is readable
by logical name. Once a label is wedged this way, **updates do not stick even when they report
success** — four different PUT variants (solution header on/off, a dedicated merge-labels action,
a minimal typed body) plus a full solution publish all returned OK and all read back empty.

The fix that actually works is **recreate, not repair**: drop the relationship (dropping any
alternate key on the column first, since a key can block the drop), then re-run the same
idempotent create script. Create-time label assignment commits fine; it's only the *update* path
that's wedged. A backfill step then repoints any rows that referenced the dropped-and-recreated
column.

**Verify labels after every batch relationship creation, not just the one you suspect** — query
`Attributes(...)?$select=DisplayName` and confirm `LocalizedLabels` is non-empty for each new
relationship. Checking only the last-created one in a batch will miss exactly the failure this
describes, since it was the earlier ones in the batch that dropped their labels, not the last.
`(four PUT variants + PublishXml all no-ops, 5 Aug 2026)`

## GlobalOptionSet binding wants the MetadataId, not the name

**When binding a column to a global choice set via `@odata.bind` fails with a message like "Guid
should contain 32 digits" — a message that reads like you passed a malformed GUID even though you
passed a name — you're using the wrong reference form.** `GlobalOptionSet@odata.bind` needs the
choice set's **MetadataId GUID**, not the `(Name='...')` alternate-key form that works for most
other `@odata.bind` targets in the Web API. Look up the MetadataId first and bind with that.

## A parental relationship is a scarce resource

**When creating a second Cascade-delete relationship on a table that already has one fails with
error `0x80047007`, that's not a transient fault — a table can have only one parental (Cascade)
relationship, full stop.** Plan which parent gets Cascade before creating either relationship;
every other parent lookup on that child table has to use a non-cascading behavior (typically
Restrict) regardless of which one would semantically deserve Cascade more.

## A picklist column can race its first write

**When a row write immediately following a new picklist (choice) column's creation fails or
behaves oddly, retry once before debugging further.** Creating a picklist column and writing a row
to it right away can race the metadata propagation; a single retry after a short pause is usually
enough.

## The virtual-table lookup rule, in full

**When registers reading through a particular lookup spin forever while the equivalent aggregate
count on the same rows returns correctly, the lookup's target is very likely a virtual table.**
Never add a lookup targeting a virtual table (a table backed by an external system rather than
stored Dataverse rows — a directory-backed identity table is the common case) onto any table that
other tables `$expand` into. The failure mode is precise: selecting the lookup column inside a
server-side `$expand` fails with SQL error 207, because the join needs a shadow "name" column that
doesn't exist in SQL for a virtual-target lookup. Top-level selects on that same column work fine
— which is exactly what hides the defect until some other table's read path tries to expand
through it, at which point every screen depending on that expand hangs. Aggregate queries
(`$apply`/aggregate-style counts) are unaffected, so a correct summary count is not evidence the
underlying detail read works. `(API-proven 10 Aug 2026)`

**The general fix, once you've hit this: drop the virtual-table lookup and its supporting
alternate key, and re-anchor identity on a plain stored column instead** (see "Identity and
contact as separate columns" below) — trading a platform-enforced link for an application-layer
one (a picker UI over the directory table plus a stored, key-enforced text/GUID column) is often
the right trade once you've hit the expand poisoning, not a downgrade to avoid.

## Alternate keys: async activation and null bypass

**A newly-created alternate key can look present in the maker portal and in metadata reads while
enforcing nothing at all — it activates asynchronously and can sit `Pending` for on the order of
50 seconds before `Active`.** Always poll status to `Active` before relying on the key for
uniqueness; testing against a `Pending` key will make it look broken (duplicates get through) when
it just hasn't finished activating.

**Separately: any alternate key stops enforcing uniqueness the instant one of its key columns is
null.** Treat this as something to deliberately decide about, not just discover:
- As a **trap**: a client that can write a record with the key column left blank can silently
  create a "duplicate" that the key never catches, because null never collides with anything
  (including other nulls).
- As a **tool**: it lets you activate a key against a table that already has legacy rows without a
  value for that column — those rows simply sit outside enforcement while every new,
  fully-keyed row is protected. This avoids a destructive backfill-or-reject choice on historical
  data when you land a new key.

## Identity and contact as separate columns

**When a single column is being asked to do double duty as both a person's verified identity and
their editable contact information, split it — that's the design that keeps typed free text from
ever being able to break an identity match.** The pattern that worked:

| role | column source | editable |
|---|---|---|
| identity | directory-sourced lookup/username field | no (read-only, populated from the directory) |
| contact | typed text field, explicitly scoped to *external* / non-directory contact info | yes, safely |

Writing a directory-sourced address into what was meant to be a general contact field destroyed
the distinction and left a supposedly-free-text field load-bearing for identity matching — any
typo there broke whatever downstream logic matched "signed-in user" against "this stakeholder,"
which in turn silently broke any rule guarding against a user approving their own request. Once
identity moved onto its own read-only, directory-sourced column, free text in the contact field
could no longer break that match. The security property here is **separation, not lockdown** — the
contact field is still fully editable, it's just no longer the thing anything trusts for identity.

## Reading a virtual identity table needs a delegated user token

**When a service-principal (app-only) context fails reading a virtual identity table with an
error like "AccessToken not found ... not called with app credentials," that's not a permissions
gap you can fix by granting more rights to the service principal — the read path itself requires a
signed-in user's delegated token.** A canvas app running as the signed-in user reads the table
fine; any app-only context (a plugin, or an automated flow whose connection is a service
principal) cannot read it at all. An automated refresh needs to run under a service **account**
connection (a real, licensed user identity) rather than a service principal, and that account
needs directory-read permission on top of table access.

**Writing to a lookup that targets the virtual table works app-only, even though reading from it
doesn't** — a service-principal `@odata.bind` PATCH to set the lookup succeeded in testing. Only
the *read* side is gated to delegated user tokens; don't assume the write side needs the same
elevation.

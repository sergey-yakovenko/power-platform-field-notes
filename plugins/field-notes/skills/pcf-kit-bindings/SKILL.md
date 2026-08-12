---
name: pcf-kit-bindings
version: 0.1.0
description: Binding contracts and authoring rules for Creator Kit / PCF code components and canvas components. USE WHEN working with Creator Kit controls (DetailsList, SearchBox, Nav, SubwayNav, CommandBar, PeoplePicker, charts), binding datasets or Table custom properties, authoring canvas components, or when a PCF control renders nothing / wrong fields with zero errors. DO NOT USE WHEN writing plain Power Fx logic (use powerfx-fieldguide) or deploying YAML (use canvas-deploy-safety).
author: Sergey Yakovenko
---

# PCF / Creator Kit Bindings

PCF code components and canvas components are a second type system layered on top of Power Fx,
and it fails almost entirely silently: wrong dataset name, wrong column name, or an under-typed
Table property all render blank or wrong with **zero compiler errors and zero App Checker
findings**. Treat every kit/PCF binding as something to verify against a primary source, never
something to infer from a property name that sounds right.

## 1. Pull the manifest before theorizing

`describe_control` returns 404 for PCF code components — it only knows stock/modern controls.
The manifest is the actual contract, and it is one query:

```bash
dataverse api request --target dataverse \
  --path "api/data/v9.2/customcontrols?\$filter=name eq '<component-name>'&\$select=manifest"
```

It distinguishes an ordinary `property` from a `property-set` at a glance — and that distinction
is exactly what several of the rules below hinge on. Before theorizing about why a control is
misbehaving, read the manifest; guessing costs a round trip through Studio per guess, and some
wrong guesses (a bad column name) fail with no error at all to even notice.

Take the compiler's own words literally: a message naming a *column* (e.g. "the specified column
'Key' does not exist") is telling you it's a data-shape problem, not a control-property problem —
several hours were once spent trying to set something as a control property that the error
message had already said, twice, was a missing column.

## 2. Dataset binding contracts

- A code component's **first dataset always binds as `Items`**, whatever the manifest calls it
  internally (`records`, `items`, `Personas` — all surface as `Items`). Using the manifest's own
  name for the first dataset produces an unknown-property error.
- A **second dataset binds as `<manifestDatasetName>_Items`** — e.g. a manifest dataset named
  `columns` persists as `columns_Items`, even though Studio's own property dropdown may label it
  with a friendlier name. Only the first dataset drops its name down to plain `Items`.
- **Datasets bind by column name, and a wrong name renders nothing and raises no error at all.**
  This is the single most expensive failure mode in this whole area — always re-verify column
  names against the manifest, never against a spec or a memory of "what it was called last time."
- `RecordKey`, `RecordCanSelect`, `RecordSelected` are **bound property-sets, not control
  properties** — see `references/dataset-binding.md` for the full manifest-verified explanation
  and why that distinction is the whole fix.

## 3. The Table-property rule: the Default IS the type

A Table custom property's `Default` is not a sample row — it is the property's **declared type**,
and it decides which fields survive the boundary when a caller passes real data in:

- `=Table()` (empty schema) type-checks against *anything*, which looks convenient, but for that
  same reason it carries **zero columns** through — every field of every caller's row is silently
  stripped.
- Pin the type instead: `=FirstN(<DataSource>, 0)` gives zero rows with the real table's full
  column set as the static type (a Default *may* reference a data source — this is proven, not
  assumed). Fallback if that's rejected: `=Filter(<DataSource>, false)`.

A type check that cannot fail is not evidence that a binding works. See
`references/dataset-binding.md` for the full experiment (three `Default` shapes, three distinct
failure signatures) and the boundary-diagnosis triage (rows erased vs. columns erased vs. a
single wrong `ColName`).

## 4. Component authoring hard limits

- **A canvas component cannot contain another canvas component.** PCF code components nest fine
  inside a canvas component; library canvas components (a menu/dialog/panel/header family) may
  only sit directly on a screen.
- **The "Access app scope" switch is mandatory, per component, with no default-on.** Without it a
  component cannot see named formulas, global variables, or any of the app's shared state — the
  error reads like a plain unrecognized-name error, not a scoping error. A component that lives
  in a **component library** can never have this switch — that is a permanent, structural
  limitation of library components, not a bug to work around.
- **Control names are unique app-wide, not per component.** Two components authored in isolation,
  each with an identically-named child control, collide the moment they're both in the same app —
  prefix every child control with its owner.
- **Event-parameter custom properties should carry an identifier, never a Record.** A Record
  parameter's `Default` *is* its declared schema (same rule as §3), so if the same component is
  reused over multiple differently-shaped tables, no single Record schema is right for all of
  them — pass a row key (Text) or similar identifier instead and re-look-up on the receiving end.
- **A component host renders at a fixed small default footprint whenever its size cannot be
  resolved from property formulas** — sizing an instance from `Parent.Width` reads the parent's
  Width *property*, not its actual laid-out width, so it silently collapses inside any
  fill/stretch layout chain. Size a component's internals against its own
  `<componentInstance>.Width` / `.Height`, never against `Parent.*`.

See `references/component-authoring.md` for the full delivery pipeline (a hand-paste path that
works without a live compile), the platform-rule table for component-definition YAML shape, and
the sizing-family digest in full.

## 5. Authority order when sources disagree

Three sources describe a control's contract, and they disagree with each other in specific,
predictable ways:

- **`describe_control` wins on property names**, for the control generation actually installed in
  a given environment — it can lag published docs by a generation, and a real compile is the
  final tiebreaker if even this is in doubt.
- **The docs win on enum accessors and semantics** — what a property means, which values are
  legal, how an event actually fires. A control-metadata tool's own "enum name" field is often an
  internal type name and gets rejected in formulas even though it looks plausible.
- **The manifest wins on PCF dataset/property-set contracts** — required columns, dataset names,
  bound vs. two-way properties.

**Do not record any of this as a fixed fact for "the" environment** — which control generation is
installed, and therefore which of these three wins on any given property, is
environment-and-time dependent. Re-derive it per environment with the three lookups above rather
than trusting a table from a previous engagement. See `references/control-facts.md` for the
environment-check procedure and the standing kit/modern-control behavioral facts that hold
regardless of generation.

## 6. Deploying the result

Once a component or binding change is authored, actually landing it in the app — compiling,
verifying what was written, and confirming it in the player — is a separate concern with its own
failure modes. See **`canvas-deploy-safety`**.

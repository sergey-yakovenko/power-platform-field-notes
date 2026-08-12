# Component Authoring

Hard limits on canvas-component `.pa.yaml` shape, a hand-paste delivery pipeline that works
without a live compile session, and the sizing family that makes component internals render at a
small fixed default footprint for no visible reason.

## Facts proven by real compiles (not static reasoning)

A batch of twelve hand-authored components, compiled for real (4 Aug 2026), drove error counts
from ~13 → 2 → 1 and surfaced facts no amount of spec-reading or agent review had caught:

- **A canvas component cannot contain another canvas component.** The compiler says
  `Component instance not allowed in Component Definitions`. PCF code components nest inside a
  canvas component fine; but library canvas components in the "overlay" family — a menu, dialog,
  panel, or header component supplied by a component library — may only sit **directly on a
  screen**. A component definition whose entire body is meant to be one of these is
  **unbuildable as specified** and needs a redesign (a placeholder control plus a documented
  alternative), not a workaround inside the component tree.
- **Library components need three specific keys, and take a *record* theme, not the JSON-string
  theme PCF components take:**

  ```yaml
  Control: CanvasComponent
  ComponentName: ExpandMenu
  ComponentLibraryUniqueName: <library-unique-name>   # required — look up per environment, see below
  Properties:
    Theme: =AppTheme.FluentRec        # a RECORD. The JSON-string theme form is for PCF, not this
    Fill: =ColorValue(Self.Theme.palette.white)
  ```

  `ComponentLibraryUniqueName` is tenant/install-specific — don't hardcode a value from a
  previous engagement. Get the real one by inserting one instance of the library component by
  hand in Studio, saving, and reading the emitted YAML back — one round-trip settles both the
  unique name and the exact property shape for the installed kit version.

  Because of this, an app that uses both PCF components and component-library components
  typically needs **both** theme shapes available as named formulas — one string (for PCF) and
  one record (for library components) — both generated from the same token source so they can't
  drift apart.

- **Control names are unique app-wide, not per component.** Two components authored in isolation,
  each independently naming a child control the same thing (e.g. two different components each
  with their own `lbl_Error`), collide as a hard compile error the moment both exist in the same
  app. Prefix every child control with its owning component's name.
- **A UDF parameter takes `DateTime`; a component CustomProperty takes `DateAndTime`.** Same
  concept, two different spellings, and each is rejected in the other's position — this is not a
  typo to "fix" toward consistency, both spellings are separately correct in their own context.
- **Component-definition-root `Width` sizing is not settled by static reasoning — verify with a
  real compile, and re-verify after any kit/platform update.** `Width: =Parent.Width` on a
  component-definition root was accepted clean across several real compiles early on (4 Aug 2026),
  contrary to every static prediction that it would fail as an unrecognized `Parent`. Later, on the
  same app (10 Aug 2026), after further changes, the identical pattern on a different component's
  root started being **rejected** — the working rule that held after that point was that every
  component-definition root needs a **literal** `Width`, not a `Parent`-relative one. Treat
  root-level sizing as something to test with a throwaway component on the actual target app before
  committing a whole design to either pattern; don't trust either "it works" or "it fails" as a
  permanent platform fact without re-checking.

## §5.4-equivalent platform rules for component-definition YAML

These are the load-bearing shape rules for hand-authoring `ComponentDefinitions:` blocks — the
kind of thing a design spec routinely gets wrong or omits, and the compiler will reject silently
plausible-looking alternatives:

| Rule | Detail |
|---|---|
| `DataType` enum members | `Text · Number · Boolean · DateAndTime · Screen · Record · Table · Image · VideoOrAudio · Color · Currency`. **`DateTime` and `Date` are not valid members here** (contrast with the UDF-parameter spelling above) |
| `Event` custom properties | require a `ReturnType` (commonly `None` for a fire-and-forget event) |
| `Parameters` | authored as a **sequence** — `- Row:` then a nested `DataType: Record` — **not** an inline map like `{Name: Row, DataType: Record}`, which some older spec examples show and which the compiler rejects |
| `AllowCustomization` | only meaningful in component-**library** source; in an app file it's ignored and flagged (a PA1017-class warning) — omit it entirely for in-app components |
| Component-definition root `Properties` | may set `Fill`, `Height`, `Width`, `OnReset`, `ContentLanguage`, `ChildTabPriority`, `EnableChildFocus` — **never `X`, `Y`, or `Visible`** on the root |
| `Property '<name>' not found on type PaModule` (a PA1001-class error) | the component name/block landed at the wrong YAML nesting level (effectively column 0). The document root accepts only a fixed small set of top-level keys — component blocks belong nested under the components-collection key, not sitting alongside it |

## Event parameters carry an identifier, never a record

A **Record**-typed event/output custom property's `Default` is its declared schema (the same
Default-is-the-type rule as Table properties — see `dataset-binding.md`), so it must mirror the
source table's shape exactly. That's fine for a component bound to one table, and unworkable for
a component reused across many differently-shaped tables — no single Record schema can be right
for all of them.

**Fix: pass a Text identifier (a row key, or the selected item's own display text) instead of a
Record.** This is also how the Creator Kit's own list/grid controls report row selection — follow
that pattern rather than fighting it with an ever-widening union-typed Record.

## Delivering components by hand — a pipeline that works without a live compile

When the compile/validate path is unavailable or unreliable for an extended stretch, components
can still be built entirely by hand in the Studio UI. Order matters:

1. **Components tab → New component**, named exactly.
2. **Turn ON "Access app scope"** in the component's property pane. *Do not skip this — see
   below.*
3. Declare the component's CustomProperties in the panel. This is the one part of the process
   that **cannot** be pasted in as YAML.
4. Paste the children YAML: extract everything under the component's `Children:` key, de-indent
   it so the first child control sits at column 0, copy it, and paste directly into the selected
   component in Studio. Studio parses full control YAML on paste and reproduces the whole nested
   tree, not just a flat list.
5. Set the component's **Output** property formulas last — they reference child controls that
   must already exist, so they fail if set before step 4.

**Step 2 is the one that's easy to skip and total in its effect.** Without "Access app scope," a
component cannot see named formulas, global variables, or anything else defined at the app level
— the error reads like a plain name-resolution failure (`Name isn't valid. '<FormulaName>' isn't
recognized.`), not like a scoping problem, so it's easy to misdiagnose as a typo. A canvas
component is encapsulated by default; this switch is what opens app scope, and it must be turned
on **per component** — there is no app-wide or inherited setting that covers it.

Two structural facts about this switch worth knowing before it costs a redesign:

- Official documentation of what the switch exposes lists global variables, collections, controls
  on screens, and tabular data sources — it does **not** explicitly mention named formulas, but
  in practice named formulas are covered too.
- **A component that lives inside a component library can never have this switch on — it's a
  permanent platform limitation, not a setting to find.** If a design depends on components
  sharing the app's theme/token named formulas, keep those components in-app rather than moving
  them to a library; moving them later forfeits that access permanently, it isn't just an
  inconvenience to work around.

A single paste attempt costs one paste action, not a full reload/recompile cycle, so this is a
genuinely cheap iteration loop for settling an uncertain property name — a rejected paste names
the offending property directly (e.g. `PA2108 Unknown property '<name>' for code component`),
which is often faster than consulting a manifest for a one-property question.

## Enhanced component properties — an app setting, not a per-component one

**Event custom properties that take parameters need an app-level setting turned on first.** Look
for it under app Settings → Updates, an option named along the lines of "Enhanced component
properties" — it is **off by default on existing apps**. Without it, an Event custom property
accepts zero parameters regardless of how it's declared, and any caller that tries to pass one
fails with an argument-count mismatch (`Invalid number of arguments: received 1, expected 0`).
Check this setting early if any component in the design declares a parameterized event — it's an
easy thing to burn time on as a "why won't my event take an argument" formula bug when it's
actually an unset app setting.

## Layout and component sizing — the fixed-default-footprint family

**A canvas-component host renders at a small fixed default size (commonly reported as 640×640)
whenever its size cannot be resolved from property formulas.** The root cause: `Parent.Width` on
a component instance reads the parent container's Width *property value*, not its actual
layout-computed width — so a component instance sized off `Parent.Width` collapses to the default
inside any fill-portions/stretch layout chain, because the parent's Width property was never
itself set to a concrete number.

The working pattern app-wide: **anchor component content top-left, and let a wrapper container
clip it**, rather than centering content inside the component. Centering content (e.g. via a
center-justify layout on the content stack) makes the failure *worse* to diagnose — the content
renders roughly 300px below the visible clipped area, so the component looks completely empty
with zero diagnostics anywhere, rather than obviously mis-sized.

**Sizing a component's internals against its own instance `Width`/`Height` (rather than
`Parent.*`) is necessary, but not sufficient by itself** — it avoids the specific
`Parent.Width`-on-instance trap above, but doesn't automatically fix every layout collapse; keep
verifying rendered size in a reloaded client, not just by reading the formulas.

Two more sizing facts in the same family, useful when a fluid/register-style layout overflows or
won't shrink:

- **AutoLayout flex children have non-zero default minimum widths** (plain text controls default
  to roughly 96px, generic containers to roughly 250px) — a fill-portions cell silently refuses
  to shrink below that default and the row overflows its card. Set an explicit smaller minimum
  width on flex cells in register/row layouts, and make sure a header row's layout mirrors the
  data row's exactly, including the trailing action column (a header's trailing padding should
  equal the action column's width plus its gap plus roughly a scrollbar's width, so header and
  data columns still line up once a scrollbar appears).
- **Dialog/field-blueprint pattern that holds up across all of this:** labels and any text inside
  an AutoLayout column need an explicit stretch alignment or they shrink-wrap and clip; buttons in
  a save/footer bar need an explicit computed width (not just intrinsic sizing) plus an
  always-visible error-message spacer so the layout doesn't jump when an error appears; footer
  wrappers should stretch rather than bind `Width: =Parent.Width` (the same trap as above); field
  hint text goes on its own full-width row rather than trying to share a row with the input. For
  repeating register-style rows, use one horizontal AutoLayout row per record plus an identical
  AutoLayout header row — alignment then holds by construction at every viewport width, instead of
  needing per-breakpoint fixes.
- A tab/selection-highlight component whose visual state is a **pure function of one input prop**
  (no internal state of its own) is immune to the two-way-binding staleness problem described in
  `control-facts.md` — prefer that shape for any component that reflects an externally-owned
  "current selection," rather than letting the component track selection internally.

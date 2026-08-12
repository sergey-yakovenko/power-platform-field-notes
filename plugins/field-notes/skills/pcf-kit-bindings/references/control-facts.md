# Control Facts

Which control-choice hierarchy to reach for, which of several disagreeing sources to trust for
what, and the specific kit/modern-control behavioral quirks that have cost real debugging time —
each one compiles clean, checks clean, and still does the wrong thing at runtime.

## Choose in this order: modern control → Creator Kit → Gallery, never skip a step to avoid an import

Reach for a **modern stock control first**, then a **Creator Kit component** (Preview and
Experimental components are fair game, not just GA ones), and drop to a hand-built **Gallery**
only when neither exists for the job. The tempting shortcut — building a Gallery of plain
controls instead of asking for a kit component to be imported — has cost real functionality more
than once:

- A hand-built "breadcrumb" out of a Gallery had no click handling at all, so it was purely
  decorative — one-click navigation to a higher level is the entire point of a breadcrumb, and a
  Gallery doesn't give you that for free.
- A hand-built command strip lost a kit command-bar's built-in overflow/coalescing behavior, which
  matters the moment the strip is narrower than its content.
- A hand-built loading placeholder lost a kit shimmer control's purpose-built first-paint
  treatment.

**Why this matters beyond tidiness:** a Gallery is an empty container. It does not give you
overflow handling, coalescing, grouping, or keyboard/accessibility semantics — you'd have to
reimplement all of that by hand, badly, every time. A missing import is a single Studio action;
treat it as a cheap ask, not a reason to downgrade the design.

Two things to check before defaulting to a Gallery:

- **A canvas-component instance cannot go inside a Gallery** — a repeating row template inside a
  Gallery must be built from plain controls, not a component instance, so a Gallery-based row
  can't reuse a component the rest of the app uses for the same visual.
- **Pick a control by its actual semantics, not just its look.** A selection-style control (state
  persists after pick) is wrong for a set of one-shot commands — used for commands, it leaves one
  item permanently marked "selected" with no way to clear it, which reads as a bug even though
  nothing crashed.

A Gallery is still the right, sanctioned choice when neither a modern control nor the kit has
anything remotely equivalent for a genuinely custom visual (e.g. a hand-rolled timeline/Gantt-style
view) — the point is to make that a deliberate, checked decision, not a default.

## Authority order when sources disagree — verify per environment, don't hardcode a table

Three sources describe a control's real contract, and they disagree in specific, load-bearing
ways. **Which one wins for a given property changes with which control generation is actually
installed, so re-derive this per environment rather than trusting a fixed mapping carried over
from a previous engagement:**

| Source | Authoritative for | How to check |
|---|---|---|
| Live control-introspection tooling (e.g. `describe_control` in the canvas-authoring MCP) | **property names**, for the control generation actually installed | query the tool directly against the live session |
| Public product documentation | **enum accessors and semantics** — what a property means, which values are legal, how an event actually fires | fetch the doc page for the specific control |
| Installed PCF manifest | dataset names, required bound columns/property-sets, enum *values* accepted by a component property | `dataverse api request … customcontrols?$filter=name eq '<component>'&$select=manifest` |
| A real compile | the final tiebreaker when the above disagree with each other | throwaway component/screen, compile, read the actual diagnostic |

**Property names:** live introspection tooling wins, because published docs describe the
*current* generation of modern controls while a given environment can be running a materially
older one. Observed disagreement, one control generation: docs claimed a `Text` control's
`FontColor` had been renamed `Color`, `FontSize` renamed `Size`, and `AcceptsFocus` removed
outright — while that environment's live introspection tooling reported `FontColor`, `FontSize`
and `AcceptsFocus` all still present under their old names. A real compile settled it: `Color`
was **rejected**, `FontColor` was **accepted** — the environment was running the older property
set the docs described as already gone.

**Enum accessors:** documentation wins, even when live introspection tooling disagrees. A
control-introspection tool's own "enum name" field is frequently an *internal* type name and is
rejected outright in formulas, even though it reads as plausible. Confirmed against a real
Studio-emitted YAML round trip, for one control generation:

| Property | Correct accessor form |
|---|---|
| Button appearance | `ButtonAppearance.Primary` / `.Secondary` / `.Subtle` / `.Outline` / `.Transparent` |
| Button layout | `ButtonLayout.IconBefore` / `.IconAfter` / `.IconOnly` |
| Text weight | the **property** is `Weight`, but the **enum** it takes is `FontWeight` (e.g. `FontWeight.Semibold`) — property name and enum name diverge |
| Text align | `Align.Left` / `.Center` / `.Right` / `.Justify` |
| Container layout | `LayoutDirection.*`, `LayoutAlignItems.*`, `LayoutJustifyContent.*` |

Treat this table as illustrative of the *pattern* (introspection wins on names, docs win on enum
accessors), not as a fixed answer for every environment — re-verify the specific accessor
spellings against a real compile whenever the control generation might differ.

**Semantics and event names are always a docs question, never an introspection-tool question.**
Documentation caught at least one bug nothing else would: an event handler assigned by exact
string name where the real event name used a different letter case than what was typed — the
mismatch matched nothing, so the handler silently never fired, with no error anywhere. Also
check docs for anything gating whether a component can see app-level state at all (an
"access app scope"-style switch) — that's a semantics question the docs cover and introspection
tooling won't surface.

**The manifest is not the canvas-facing name.** A PCF component's first dataset always binds as
plain `Items` regardless of what the manifest itself calls it internally — see
`dataset-binding.md` for the full rule. And **docs can describe a newer control version than what
is actually installed** — cross-check any dataset/property claim from docs against the manifest
of the version actually deployed, not just the docs' description of the control family in
general.

## Kit and modern-control behavioral facts

These are specific, repeatable behaviors of common Creator Kit / modern controls, each one worth
knowing before it costs a debugging session — none of them raise any compiler or checker
diagnostic:

- **A navigation control's "selected key"-style property, when it's a two-way bound property, is
  two-way bound — a static binding never re-asserts after the user clicks.** After a user click,
  the control keeps its own internal selection state; a static input binding only re-applies when
  its *value changes*. The fix pattern: bind it to something that changes on every screen
  transition (e.g. `If(App.ActiveScreen = <thisScreen>, "<this screen's key>", "")`) so a genuine
  value change forces the control to re-sync on every screen. Don't assume an `InputEvent`-style
  programmatic-set capability exists unless the control specifically documents one (many
  navigation controls support only a focus-set event, not a selection-set event).
- **Read a two-way control's output in `OnChange`, never in `OnSelect`.** `OnSelect` can fire
  *before* the bound output property has actually committed its new value — reading
  `Self.Selected.<field>` from an `OnSelect` handler was observed to be intermittently one click
  stale, producing a wrong-destination navigation on an otherwise-correct click. The documentation
  for this class of control typically says outright that selection state updates are reported
  "via the OnChange event" — trust that literally.
  `(player-proven, 7 Aug 2026; static/compile-time checks never caught it)`
- **A hierarchical/subway-style nav control's top-level rows need an explicitly blank
  parent-key**, not a row's own key or nothing at all — a row that points at itself (or is left
  unset in a way that resolves ambiguously) as its own parent is neither correctly top-level nor
  correctly a child, and is silently dropped from the rendered tree with no error. Separately, a
  genuinely empty dataset for this class of control can render a handful of generic numbered
  placeholder nodes instead of an empty state — don't mistake that for real data. This class of
  control has also shown a first-visit initialization race: placeholder nodes briefly show
  alongside real data on first load, which then clears correctly on leaving and re-entering the
  screen — worth knowing so a first-load flash isn't misread as a data bug.
- **A grid/DataTable-style control commonly renders its columns in *reverse* authored order** —
  author the column list already reversed rather than fighting it per screen. Also for this class
  of control: its own field-picker UI can emit formulas that its own compiler then rejects, so
  hand-author column formulas rather than trusting the picker's output; row-open/selection is
  typically wired through `OnChange` + a `Selected` output, not an `OnSelect`; a single grid
  instance cannot `Switch()` its `Items` between two differently-typed sources; and if a design
  tool's palette offers a generic "Table" insert, check what control type it actually persists
  as — a generic-looking insert can silently become the modern grid control regardless of the
  label in the palette.
- **A file/attachment column on a Dataverse-bound form typically commits only when the form is
  submitted**, not when the file picker itself reports a change — the attachment control merely
  *stages* the file locally; check the form's own "has unsaved changes" signal as the real
  pending-write indicator, and don't assume a file is persisted just because the picker shows it
  selected.
- **A kit command-bar's items can render as accessibility menu items with an icon-glyph prefix
  drawn from a private-use-unicode-area icon font** — when comparing or asserting on a command
  label in automated testing, strip non-ASCII characters before comparing text, or the comparison
  will fail even though the visible label matches.

Related standing facts, filed with their own detail elsewhere in this skill set: the
Table-property Default-is-the-type rule and the empty-schema trap (`dataset-binding.md`); the
component-instance sizing/640-default family (`component-authoring.md`).

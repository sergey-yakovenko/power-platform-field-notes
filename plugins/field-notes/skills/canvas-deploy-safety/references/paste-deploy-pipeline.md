# Paste-Deploy Pipeline

When the compile service is unavailable, dead, or you deliberately want a smaller blast radius
than a full-directory compile, Studio's own YAML paste (⌘V into the designer) is a working,
pairing-independent deploy path. It is not a degraded fallback — whole app shells, whole screens
and whole components have been deployed through it. This reference covers the component pipeline,
the paste/fx/tree mechanics that will otherwise cost you a wasted round trip, and whole-screen
recovery.

## The component pipeline

Building a canvas component by hand, without the compile service, works in this order — **order
matters**:

1. **Components tab → New component**, named exactly as it must be referenced elsewhere.
2. **Turn ON "Access app scope"** in the component's property pane. Do not skip this.
3. **Declare the component's custom properties in the panel.** This is the one part of the
   pipeline that cannot be pasted — it must be built through the UI.
4. **Paste the children YAML.** Extract everything under the component's `Children:` node,
   de-indent it so the first child sits at column 0, and paste it with the component's root
   selected. Studio parses full control YAML and reproduces the whole nested tree from a single
   paste.
5. **Set the component's output-property formulas last** — they typically reference children that
   must already exist in the tree, so setting them before step 4 will fail to resolve.

**Step 2 is the one that's easy to skip and total in its effect if you do.** Without it, a
component cannot see any app-level named formula or app-scoped theme/token value — referencing one
fails with an "isn't recognized" error, because a canvas component is encapsulated from the app by
default and this switch is what opens that scope. It is required on **every** component that needs
app-level formulas, not just some of them.

Two structural facts worth knowing about this switch: it's documented to expose global variables,
collections, screen controls and tabular data sources to the component — named formulas aren't
called out explicitly in that list but are covered by it in practice — and a component that lives
in a **component library** (as opposed to living in the app itself) can **never** get this access,
at all. If a component needs app-level named formulas or theme values, keep it in-app; moving it
to a library forfeits that access permanently.

A single paste attempt costs one paste, not a Studio reload, so this is a cheap iteration loop
compared to the compile service — use it to settle uncertain property names quickly, since a
rejected paste names the offending property directly (e.g. "unknown property X for code
component").

`(pipeline proven 4 Aug 2026, unblocking component delivery on a day the compile service was
unusable)`

## Paste and anchor mechanics

Studio's paste target depends on exactly what's selected when you paste, and getting this wrong
silently lands content somewhere other than where you meant it to go:

- **⌘V pastes as a SIBLING of the current selection** — it lands inside the selection's *parent*.
  To paste content **into** a container, select a *child* of that container (or the container
  itself, per the refinements below), not the container's own parent.
- **A paste anchored on a control that accepts children of its own — a data-grid-style control in
  particular — silently falls back to the screen root** instead of landing where you intended.
  Anchor pastes on a plain control or a component instance instead.
- **Anchoring on a plain container pastes INTO it** (not as a sibling, not at the screen root).
- **Selecting the screen itself and pasting lands the content at screen root** — this is the
  reliable way to land an entire top-level subtree in one paste.

**After any paste, verify the pasted control's parent structurally** — the control merely
existing somewhere in the tree is not proof it landed in the right place — **and close out with a
rendered screenshot**, not just a DOM/tree check. A tree check can read "correct" on a screen that
is visually destroyed.

## Geometry, alignment, and other paste side effects

- **A whole-screen paste mutates geometry** — position values on repeated/template children can
  drop or clamp unexpectedly — **and the synced-down YAML can lie about it**, still reporting the
  originally-authored value while the live document and rendered layout hold something else.
  Verify layout with rendered bounding boxes or by reading the value directly in the formula bar,
  never from synced YAML alone; repair by re-asserting the correct value through the formula bar.
  A fluid, auto-sizing layout with no fixed position values to begin with is immune to this class
  of drift by construction.
- **A paste drops container-alignment properties on group/container controls** (this property
  tends to survive on simple text controls, just not containers). A properties-pane edit to the
  same setting persists correctly where a paste of it does not — but watch for a same-named-looking
  control near the top of the pane that actually controls a *different*, related layout property;
  they're easy to confuse. When the alignment property won't serialize through any paste route,
  stop fighting it and give the child an explicit width instead. The synced-down YAML is
  unreliable in **both directions** about whether this property is actually present.
- **A component instance's width cannot be reliably landed in the serialized document by any
  paste or formula-bar route** — not via a direct formula write, not via a paste under any
  alignment mode, not via a fresh re-paste; there is also no properties-pane field for it in some
  cases. The workaround is to size the *hosting* container instead of the instance itself (with an
  appropriate fixed-width floor for anything hosting a wide child), or to size around the
  limitation entirely by moving the sizing-sensitive content out of the instance. Note that
  Studio's live preview mode runs the live document, where a formula-level width write can appear
  to work — while the actually-published package does not carry it. Don't trust preview alone for
  this specific class of check.

## Tree, fx-bar, and reload mechanics

- **In the Studio tree, an expanded tree item's clickable box spans its children** — clicking
  toward the center of that box can select a child instead of the item itself. Click the item's
  own row/label element specifically, matched by its exact name, to select the item you mean.
  "Reorder → Move up/down" in the tree's context menu silently no-ops on controls that have no
  visual position on the canvas; inside a repeated/template structure, that submenu instead
  controls z-order, not list order. **Never touch the properties pane while a repeating/gallery
  control is selected for an unrelated reason** — an accidental layout-related click can silently
  re-bind every template field to an auto-assigned column.
- **The formula-bar property picker's type-to-filter behavior is not reliable** — typing a
  property name and pressing Enter can select the wrong, unrelated property that happens to share
  a prefix. Pick properties by an exact click on the intended option, not by typing and confirming.
  Pressing Escape reverts the formula editor's pending edit. Don't rely on the editor's
  parenthesis auto-closing behavior in either direction — insert whole formulas via a full
  clipboard paste or programmatic text insertion instead of typing them character by character.
  The property picker doesn't expose every settable property (some, like a button's width and
  height, are pane-only). Pasting a multi-row table literal into a custom property's default value
  through the formula bar condenses it down to a single row (the *type* is preserved, so this is
  usually harmless for a property whose schema, not its literal sample rows, is what matters). The
  formula-bar's underlying model **excludes the leading `=`** of a formula — pasting text that
  still has the leading `=` on it serializes as a doubled `==` and the property silently renders
  blank. The formula editor's own readback of a long formula can be **windowed** around the
  cursor, not showing the whole value — treat any "does this look right" check against the visible
  editor text as unreliable for long formulas; sync down and diff (normalized for whitespace)
  instead.
- **A Studio reload can silently void an entire delete-then-paste-then-save round** — one tell is
  the browser URL unexpectedly picking up an extra query parameter it didn't have before. Verify
  every delete actually landed (the control is genuinely gone from the tree) and sync-diff before
  publishing anything; reconnect your tooling after any unexplained URL change.
- **Using the Insert command (from the command bar) inserts into the currently-selected
  container** — this is the anchor-risk-free way to add a single new control, since it doesn't
  depend on the sibling-vs-into-container ambiguity above.
- **Studio's own live Preview mode runs the live document**, which makes it useful for fast
  geometry checks (seconds, versus a full publish cycle) — but validate that Preview is actually
  showing you what you think with a trivial, unambiguous probe first (e.g. a bare notification
  banner), since it also renders app-level notification banners which can be mistaken for
  something else. Pressing Escape exits Preview back into edit mode, where clicks select controls
  instead of firing their click behavior — a test "click" performed in edit mode by mistake is a
  null test.

## Whole-screen restore

**Studio's YAML paste restores a WHOLE SCREEN, independent of whether the coauthoring session is
paired at all.** This is the standing recovery path whenever a deploy attempt is stranded halfway
— for example, a screen deleted mid-procedure with no way to compile a fix back in. Recovery:
extract everything under the target screen's `Children:` node from your authored source,
de-indent it to column 0, select the (now-empty) screen in Studio, and paste. One recorded
recovery this way restored 92 controls — names, order and nesting byte-identical to the authored
source, formulas intact, verified by a full tree diff. Screen-level properties (fill, on-visible
logic, etc.) typically survive independently on the server even through a broken deploy attempt,
so only the child tree needs restoring.

# Player Verification

**A clean compile, a clean checker, and a successful publish together prove nothing about what
actually happens when a real user opens the app and clicks through it.** Treat a formula, a click
path, or a control's behavior as unverified until it has actually executed in the running player
against real data — not merely compiled, not merely passed a static checker. Compile-clean defects
that only ever surface in the player include: click targets nobody had ever actually clicked
(an OnSelect that was never reachable from the control type it was written on), transparent-style
buttons that render as solid, opaque hit targets in the player despite looking transparent in the
designer, and layout/positioning drift introduced by a deploy step that no static check catches.
A formula or interaction with zero real callers has, in a very literal sense, never run.

## The publish-and-refresh loop

Publishing an updated package does not mean an already-open player tab is showing it.

- After publishing, an open player tab typically surfaces an "you're using an old version"-style
  banner; you must click through it (its Refresh action) to actually load the new package.
- **Banner-absent does not mean current.** An interrupted page reload can leave a tab serving the
  *old* package with **no banner ever appearing** — either because the reload didn't fully
  complete, or because you checked too soon after publishing for the banner to have appeared yet.
  Treat "no banner" as unproven, not as confirmation you're on the latest package. Only a
  banner-found-then-refreshed cycle (or an unambiguous fresh navigation to the player) is
  trustworthy evidence you're testing the current package.
- The player app itself typically runs inside its own iframe within the hosting page — locate it
  by scanning frames for the one whose URL matches the runtime player, rather than assuming the
  top-level page is what you're interacting with.

## Markers, visibility, and false verdicts

- **Hidden screens stay in the player's DOM.** A screen that is not currently visible is not
  necessarily absent from the document — a marker search that doesn't filter by visibility will
  match content on hidden screens and produce false positives about what's "on screen."
  Visibility-filter every marker you use to assert something is present (an explicit visible/width
  check, not just element existence).
- **Input placeholder text is not a text node** — searching for it as literal page text will not
  find it; check the control's placeholder property or attribute instead.
- **Raw DOM text extraction on a control can return garbage even when the control renders
  correctly** — verify by screenshot, or by reading the value directly in the designer's
  properties pane, rather than trusting extracted DOM text alone as ground truth for what a
  control shows.
- Kit/library navigation controls can prefix their item labels with a non-printable icon glyph —
  strip non-ASCII characters before comparing a label's text against an expected string, or the
  comparison will fail even when the label is correct.

## Click mechanics

- **A synthetic DOM click (e.g. calling `.click()` directly on an element) on a kit/library
  navigation control can produce false "navigation went to the wrong place" results.** Only a real
  mouse-event click at the control's actual on-screen bounding-box coordinates is trustworthy for
  verifying navigation behavior in these controls.
- A role-based/locator click (which auto-scrolls the target into view first) is preferable when
  the target may be off-screen and coordinate-based clicking can't reach it; use whichever
  mechanism actually reaches the target reliably for the control in question, and don't assume one
  approach is universally correct.
- If the player runs inside an offset iframe, remember that mouse-driven clicks and
  DOM-coordinate-based lookups (like element-at-point) use **different coordinate spaces** —
  mixing page coordinates with in-frame coordinates produces phantom "click landed on the wrong
  thing" diagnoses that are actually just a coordinate-space bug in the test, not the app.
- Clicking an already-selected item in a navigation control is often a designed no-op (its change
  handler is not expected to fire again for the same selection) — don't read "nothing happened" on
  a re-click of the current item as a defect.

## Interacting with specific control types

- A date-picker control that ignores typed text, and clears on Escape rather than reverting, needs
  its value set by picking a day in its calendar grid, not by typing.
- A combobox-style control is reliably driven by: click to open, type to filter, click the desired
  option; pressing Escape closes the popup without reverting an already-made selection.

## The underlying principle

None of the above is really about test mechanics for their own sake — it's the practical
consequence of one fact: **a formula that compiles clean, an OnSelect that's wired up, or a filter
that returns the right shape of data in isolation can still be dead code until it has actually
executed, once, in the running player, against real data.** Static analysis (the compile service,
any app-level checker, the designer's own client-side checker) has repeatedly passed code that
then failed the instant it was first actually exercised — because static analysis cannot see
runtime-only failures (certain conversions that only fail at execution time, navigation through
data that resolves to nothing at runtime, first-visit initialization races in embedded components,
and so on). When a surface renders empty or behaves unexpectedly despite every checker being
green, the fix is to probe the actual execution chain link by link with disposable output (e.g.
temporary labels showing intermediate values), not to re-read the formula and reason about it
statically again. Runtime-specific correctness rules for Power Fx itself — the actual bombs this
principle exists to catch — are covered in `powerfx-fieldguide`; this reference is only about
proving, mechanically, that a given path has actually been exercised.

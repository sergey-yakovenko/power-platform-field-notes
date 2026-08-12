---
name: canvas-deploy-safety
version: 0.1.0
description: Safety protocol for writing to a Power Apps canvas app through the canvas-authoring MCP (compile_canvas / sync_canvas) and for verifying what is actually in an app. USE WHEN compiling or deploying canvas .pa.yaml, when a compile returns FAILED or zero diagnostics, when "No active coauthoring canvas designer session" appears, when deciding how to deploy a screen or component change, or when app state after a write is uncertain. DO NOT USE WHEN only reading schemas or authoring YAML offline with no write intended.
author: Sergey Yakovenko
---

# Canvas Deploy Safety

`compile_canvas` (the canvas-authoring MCP's validate-and-write call) does not behave like a
normal compiler. It writes to the live app document even when it reports failure, it needs a
live Power Apps Studio designer session to validate anything at all, and its return value tells
you almost nothing about what actually landed. Treat every write against a canvas app you care
about as a procedure with its own verification step, not a single tool call you trust the
response of.

## 1. The prime rule: validation status ≠ write status

A `FAILED` result and a clean write are independent facts. A run can report `Validation FAILED`
and still have written its YAML to the app; a run with zero errors can report `FAILED` too,
because warnings alone are enough to flip the status. **The only way to know what is actually in
the app is `sync_canvas` to a scratch directory, followed by a diff — after every compile,
successful or not.** Never sync into your working directory: it overwrites same-named source
files and will destroy authored content that hasn't been re-pasted anywhere else.

`(observed on four consecutive FAILED compiles that all wrote, 4 Aug 2026)`

See `references/write-semantics.md` for the full write-semantics rule set, including why a clean
diagnostics count doesn't mean clean, and how a session that looks dead can still write partial
damage.

## 2. The full-directory rule

The source directory you hand to `compile_canvas` **is** the app definition — the call does not
merge a partial directory into the existing app, it replaces the app with what you sent. A
directory holding one screen was once validated (with errors) and, because a failed compile
still writes, each retry replaced the live app document a little more — deleting 17 of 18
screens in the process.

Recovery is the maker portal: app → **Versions → Restore** the last good version. That restore
fails with "locked by user … wait at least 15 minutes" until every authoring session on the app
is closed — every Studio tab **and** the MCP server process backing the coauthoring session (kill
it; a reconnect re-mints it later).

Operational consequence: **only ever compile the complete working directory.** For a
single-screen or single-component change, prefer the paste path in
`references/paste-deploy-pipeline.md` — its blast radius is one screen or component by
construction, not the whole app.

## 3. Session liveness is a gate

Before any compile that carries new content (not a byte-identical no-op), classify the
designer-session state per `references/pairing-protocol.md`. A dead-session compile is not a
safe no-op: it can write a **mutilated tree** — the control tree present, but scores of
value-carrying properties (text, fill, event handlers, item bindings) silently dropped, which
renders as black boxes rather than raising any error.

The pairing reference covers the classify states (live / dead / unproven), why a byte-identical
probe proves nothing, the escalation ladder for reviving a dead session, and when to stop trying
and switch to the paste path instead.

## 4. Merge semantics

A compile write is a **merge**, not a replace-in-place of only what you touched, and several of
its behaviors are easy to get burned by:

- **Child order is service-owned.** Authored sibling order does not reliably survive a merge
  that adds controls among existing ones. Forcing authored order needs a delete-then-recreate
  across two separate compiles — and the delete must be **sync-verified as landed** before the
  recreate runs, or two back-to-back compiles collapse into a single merge that never actually
  deletes anything.
- **Even a property-only merge can scramble a screen's rendering** — a change touching two
  properties on one existing control, with zero children added or removed, once scrambled the
  whole screen's layout. Reload a client and verify rendering after any merge that touches an
  existing screen, not just after ones that add or remove controls.
- **A canvas-component instance sitting among plain controls in an AutoLayout container breaks
  ordering even on a fresh create** — it can render first regardless of authored position. Wrap
  every component instance in a plain container so no instance sits directly at an
  ordering-sensitive level.

## 5. Checklist — the compile loop

1. Confirm you are compiling the **complete** working directory, never a subset (§2).
2. Probe session liveness with harmless, content-carrying input before trusting the session is
   live (`references/pairing-protocol.md`).
3. Compile.
4. `sync_canvas` to a scratch directory and diff against what you authored — never trust the
   return status alone (`references/write-semantics.md`).
5. Reload the Studio client and verify rendering, especially for any screen the merge touched
   (§4).
6. Publish.
7. Verify in the **player** — publishing a package and reading a clean compile prove nothing
   about what a user will actually see or click (`references/player-verification.md`).

A clean compile also proves nothing about whether the formulas it deployed actually *run*
correctly — that is a separate, later kind of failure. Once a change is deployed and
player-verified for rendering and navigation, hand off correctness of the Power Fx itself to
**`powerfx-fieldguide`**.

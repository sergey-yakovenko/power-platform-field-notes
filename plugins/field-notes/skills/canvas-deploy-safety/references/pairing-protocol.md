# Pairing Protocol

Compiling and writing canvas `.pa.yaml` requires a **live Power Apps Studio designer
(coauthoring) session** for the target app — not just a valid connection from your tooling. This
reference is the full protocol for classifying that session's state, escalating when it's dead,
and knowing when to give up and use the paste path instead.

## The three states: live, dead, unproven

A compile call returns one of three effective states, and they are not the two you'd guess:

- **Live** — the session is registered and the service can validate your content for real. A
  compile with genuine diagnostics (errors or warnings that describe your actual content) is
  live. So is a clean compile you've confirmed with a canary (see `write-semantics.md`).
- **Dead** — the response carries a line to the effect of "no active coauthoring designer session
  detected." Content-carrying compiles against a dead session can silently write **mutilated**
  output — see `write-semantics.md`.
- **Unproven** — a byte-identical (no-op) compile came back *without* the dead-session warning.
  This is not evidence of "live." It's evidence of nothing. See the null-test trap below.

The tell for dead is unambiguous: the "no active coauthoring session" line is present when dead
and **entirely absent** when live — there's no partial or ambiguous form of it.

## The null-test trap

**When probing session liveness, a byte-identical (no-op) sync-and-compile proves nothing about
pairing — do not trust a clean result from one.** The service only performs the
designer-session lookup at all when the payload you send **differs** from the document already
stored. If your probe content is identical to what's already there, there's no merge to perform,
so there's no lookup, so the response comes back "live" regardless of whether a real session is
actually registered. Every byte-identical probe in one large corpus answered live — 26 for 26 —
which is exactly what you'd expect from a test that never actually exercises the thing it claims
to test.

**The only real probe is a compile carrying genuinely different, harmless content.** Treat a
clean byte-identical response as "unproven," never as "confirmed live."

`(root-caused 6 Aug 2026, from direct MCP-protocol instrumentation plus a full multi-day replay of
compile-call history)`

A second, related fact worth knowing before you start troubleshooting client-side: **the calling
tool performs no designer-session discovery of its own.** A compile is one HTTP call; the verdict
about whether a designer session exists is computed entirely inside the service's response to that
one call. No client-side ritual — reconnecting, waiting, restarting the MCP process, restarting
the browser — can reach past that and directly fix a dead session. Those actions only matter to
the extent they cause a **real Studio session to register**, which is the actual precondition
(next section).

## Escalation ladder

Work these rungs in order. Each one is a genuine precondition observed to matter; none of them is
guaranteed to work, because the underlying pairing mechanism is service-side and partially opaque.

**Rung 1 — there must be a genuine edit happening inside Studio, not just an open tab.**
Dead-to-live transitions have never been observed without a real edit action taking place inside
the Studio designer session — merely having the app open, or foregrounded, is not sufficient.
This edit can come from a human or from an automated browser session driving Studio directly
(clicking a tree item, typing, etc.) — both have produced a live pairing. Connect recency predicts
nothing on its own: successes have followed a connect by anywhere from 1 to 21 minutes, and
failures have followed a connect by as little as 9 seconds. Editing is *necessary*, but — per the
outage-recognition rung below — not always *sufficient*.
`(dead→live transitions all preceded by real Studio editing, 6 Aug 2026; agent-driven editing
confirmed sufficient too, 10 Aug 2026)`

**Rung 2 — after any Studio reload, wait before the first compile.** Session registration after a
page load takes on the order of a minute or more, not seconds. A "the reload didn't fix it"
observation once turned out to be measured only 19 seconds after the reload, while Studio was
still loading — a false negative from testing too early. Wait roughly 60–90 seconds after any
reload before treating a subsequent dead result as meaningful.

**Rung 3 — after a full browser restart, waiting does not recover the old pairing; a fresh
connect is required.** Two compiles stayed dead more than 90 seconds after Studio was confirmed
back in edit mode following a full browser restart; a fresh connect call then paired live on the
first try. Protocol after any full browser restart: reopen Studio in edit mode, wait ~60 seconds,
issue a fresh connect, then probe.

**Rung 4 — check for and clear contending sessions, but know the cost of doing so.** Multiple
authoring-server processes can be alive at once — one per active tooling session, including
stale/backgrounded ones from earlier work — and contention among them is a plausible cause of
registration failing outright across several spaced reload attempts. Kill stale processes before
diagnosing anything further. The cost: killing the process backing your *current* session also
kills its connection, and you'll need to explicitly reconnect your own tooling before continuing.

**Rung 5 — recognize an outage and hard-exit to the paste path.** Ordinary dead streaks run
roughly 6–50 minutes and resolve with the rungs above. A qualitatively different failure mode also
exists: one documented outage held 17 consecutive dead content-carrying compiles across 3.5+
hours, surviving a full browser restart, a fresh coauthoring session, and an exact client/server
version match (ruling out a version-mismatch explanation). This class of failure is a known,
open, upstream issue — tracked against the coauthoring service itself
(`microsoft/power-platform-skills` issues **#189** and **#266** at time of writing), not something
any client-side workaround fixes. **Budget roughly 3 rungs / ~30 minutes of genuine attempts; past
that, stop spending time on pairing and deploy via the paste path** in
`paste-deploy-pipeline.md` instead.

## Anti-rituals — actions that look like troubleshooting but are not

These have each been tried and shown not to move the needle, on their own:

- **Repeating a byte-identical probe hoping for a different verdict.** See the null-test trap —
  it cannot ever report dead, live or not, so repeating it teaches you nothing.
- **Calling connect again and again with no Studio-side activity.** Connect mints a new session ID
  on the calling side, but that alone does not make the service find a Studio designer session —
  a Studio designer session either exists (from real Studio activity) or it doesn't.
- **Comparing your tooling's session ID against Studio's own "coauthoring session ID" (visible in
  its About panel) to check whether they're paired.** These are never the same ID, on any run —
  they cannot be compared to detect anything.
- **Waiting after a full browser restart instead of issuing a fresh connect.** See Rung 3 — this
  specific combination has been tested and does not recover pairing; the fresh connect is the
  step that matters.
- **Assuming a version mismatch between your tooling and Studio is the cause of a long outage.**
  Tested directly during one multi-hour outage — client and server versions matched exactly, and
  the outage persisted regardless.
- **Applying an unrelated fix for a superficially similar upstream issue that turns out not to
  apply to your integration path** (e.g. an environment-variable workaround documented for a
  different client integration than the one you're using) — verify the fix actually targets your
  code path before spending time on it.

## Damage control

Whenever a content-carrying compile ran against a session whose liveness you weren't fully
certain of, do not trust the result either way. Sync down and run a **structural** property diff
— names *and* values, not a plain text diff, since the server reorders properties alphabetically
and elides anything equal to a default. If you find a mutilated tree (control structure intact,
but properties like text, fill, item bindings or event handlers dropped), repair by pasting the
whole affected screen fresh from your authored source, per `paste-deploy-pipeline.md` — this
repair path does not depend on the coauthoring session being paired at all. A live, correctly
paired session is not by itself a guarantee the merge left the screen intact either — see the
merge-semantics section of `SKILL.md`: even a property-only merge, with zero children added or
removed, has scrambled a screen's rendering. Reload and verify rendering after any content-carrying
compile, not only after a session you suspected of being dead.

Separately, note that `sync_canvas` (the read path) has its **own**, different Studio-gating
condition: it needs the connect call to have happened *while Studio already had the app open*.
"No files returned" from a sync most often means connect ran too early, not that the app is
actually empty — reconnect after confirming Studio is open in edit mode, then sync again.

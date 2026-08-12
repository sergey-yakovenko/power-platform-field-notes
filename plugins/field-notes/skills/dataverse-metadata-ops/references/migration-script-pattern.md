# Migration Script Pattern

How to structure and run scripts that change Dataverse schema and backfill data against them, and
the toolchain gotchas specific to that kind of script.

## The pattern: small, idempotent, numbered waves

Schema migrations that worked reliably were split into small scripts, each covering one concern
and each safe to re-run without side effects:

- **One script per concern, not one script per migration.** A batch of related changes split
  cleanly into: a script for new choice/option sets, a script for new columns, a script for new
  relationships, a script for seeding reference/config rows — rather than one large script mixing
  all four. When a later change needed a new lookup, its own linking/backfill logic, a denormalized
  key column, and an alternate key, that became four small scripts run in sequence rather than one
  script trying to do all of it atomically.
- **Every script is idempotent.** Re-running a script that already applied its changes should be a
  no-op, not an error and not a duplicate write — check for existing state (does the relationship
  already exist, does the row already have this value) before creating or writing.
- **Linking/backfill logic matches on something exact, never fuzzy.** When repointing existing
  rows onto a new column or relationship, match on an exact key (an exact email address, an exact
  ID) — never a fuzzy match like approximate name matching. A fuzzy match can silently attribute a
  record (an approval, a decision) to the wrong person or row, which is a much worse failure than
  simply leaving a row unlinked for a human to resolve by hand.
- **Backfill is followed by a read-back go/no-go check, not assumed from the write response.**
  After a backfill/repoint step, count how many target rows are still blank on the column that
  should now be populated, and treat a non-zero blank count as a failed migration step, not a
  detail to fix later. A migration that reports success but leaves any row unrepointed is a defect
  in the migration, not an acceptable partial result.
- **Environment confirmation happens before any write, every time, not just once at setup.** A
  tenant with multiple environments can have its default CLI auth profile pointing at a *different*
  environment than the one you intend to change — verify the active environment/organization
  immediately before every write script runs, not just when the project started.

## A column added purely for delegation needs a maintainer

**When a column is added specifically to make a formerly two-hop (non-delegable) lookup into a
one-hop comparison, don't consider the migration finished once the column and its backfill are
done — something has to keep writing to it going forward, or it silently rots.** A denormalized
column created by a migration script is correct on the day it's backfilled and then stale forever
after unless a business rule, a real-time workflow, or the application's own write path
maintains it whenever the source relationship changes. A blank or stale denormalized column
doesn't error — it just silently drops the affected row out of every count and filter that reads
the column, which is a much worse failure than an obvious error. Treat "who maintains this column
going forward" as a required, not optional, line item of the same migration that introduced it.

## The Python SDK trap: an interactive-auth hang looks like a hang, not an error

**When a script that should hit the Dataverse Web API just sits there producing no output at all,
suspect a client library silently trying to fall back to interactive device-code auth rather than
assuming the network call itself is slow.** An SDK client that can't silently reuse an existing
CLI token cache (for example, because the cached profile is a service-principal identity the SDK
doesn't know how to reuse) can block on an interactive device-code prompt with **zero output** —
it hangs rather than erroring, which is much harder to diagnose than a clean failure.

**The reliable path: use the raw Web API through an already-authenticated CLI** rather than an SDK
client that manages its own auth session — a CLI whose auth is already working for interactive use
generally authenticates fine for scripted API calls too, and skips the interactive-fallback trap
entirely.

**Never pipe a long-running script through `tail` or `head`.** Both buffer their input until EOF,
so if the underlying process is actually waiting on an interactive prompt, you'll see nothing at
all rather than the prompt that would tell you what's wrong — the buffering hides exactly the
signal you need to diagnose a hang.

## Toolchain gotchas that generalize

- **A CLI's `--path` argument for a REST-style call may require a relative path, not an
  absolute one.** A leading `/` can produce a misleading error (something like "Absolute URL host
  ''" rather than anything mentioning the path format) that reads like a connectivity problem
  rather than a formatting one. If a REST-passthrough CLI call fails with an URL-host-shaped error,
  check whether the path argument itself starts with `/` before looking anywhere else.
- **A metadata query with an unsupported `$filter` expression can silently return an empty result
  set instead of erroring.** Don't take an empty result from a metadata query (e.g. "does this
  table exist") as proof of absence until you've confirmed the filter expression you used is
  actually supported — an unsupported filter and a genuinely nonexistent object look identical from
  the caller's side. Filter client-side (fetch broadly, then filter in the script) when in doubt.

## The `DOTNET_ReadyToRun=0` fix for a machine-wide CLI crash

**When a .NET single-file CLI starts throwing `System.AccessViolationException` with a different
stack trace on every run, always somewhere in the HTTP path, and this happens across unrelated
projects on the same machine — don't chase it as an auth or network problem.** The trap: commands
that never make an HTTP call (like listing cached auth profiles) keep working fine even while the
HTTP-calling commands crash, so the failure masquerades as an authentication problem when it isn't
one.

Things that do **not** fix it: reinstalling the CLI, killing any background daemon process, various
write-protection/execute environment flags, bypassing proxy environment variables, or clearing the
CLI's single-file extraction cache.

**The actual fix: set `DOTNET_ReadyToRun=0` in the environment before invoking the CLI.** The root
cause is corrupted ReadyToRun precompiled images; forcing the runtime to JIT instead
(`DOTNET_ReadyToRun=0`) resolved it completely across several hundred subsequent calls with zero
failures. Set this in every migration script's subprocess environment rather than relying on it
being set globally in the shell, so the scripts keep working regardless of who runs them or from
where. `(root-caused 6 Aug 2026)`

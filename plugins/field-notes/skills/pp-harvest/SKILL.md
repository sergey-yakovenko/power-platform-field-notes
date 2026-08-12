---
name: pp-harvest
version: 0.1.0
description: Harvest new Power Platform lessons from a working project into the field-notes skills. USE WHEN the user runs /pp-harvest, asks to fold recent lessons into the field-notes plugin, or at a commit boundary after a session that corrected or discovered platform behavior. DO NOT USE WHEN the lesson is project-specific (schema names, business rulings) - those belong in the project's own CLAUDE.md.
author: Sergey Yakovenko
user-invocable: true
---

# pp-harvest

Fold hard-won platform lessons out of a working project's `CLAUDE.md`, `docs/`, and memory
files, and into the field-notes plugin's domain skills — so the next project starts with them
already known instead of re-learning them the hard way. This is a maintenance workflow, run
periodically (typically at a commit boundary), not a build step.

Run the steps below in order. Each step names exactly what to read, what to produce, and what
to hand to the next step.

## 1. Locate sources and the last harvest marker

The harvest target is the field-notes **source checkout** — the git repo containing
`plugins/`, `scripts/check.sh`, and `HARVEST-LOG.md` at its root (on this machine,
`~/Development/power-platform-field-notes`). This is *not* simply "a few levels up" from this
skill: the source layout is `plugins/field-notes/skills/pp-harvest/`, so the repo root is four
levels up (`skills/pp-harvest/../../../..`) from a source checkout — but an **installed
plugin-cache copy has no marketplace root at all**, since the cache only copies the plugin
directory (`plugins/field-notes/`) and that copy is overwritten on every update. Never write to
a plugin-cache location.

If this skill is running from an installed plugin cache, or the checkout location is otherwise
unknown, **ask the user for the checkout path before proceeding** rather than guessing a
relative-path depth.

Read `HARVEST-LOG.md` at that repo root. Find the row (if any) for the working project — the
project whose lessons are being harvested, identified by name or path. That row's "up to commit"
column is the baseline: every commit up to and including it has already been harvested and must
not be re-harvested.

If the working project has no row yet, the baseline is the empty tree — harvest the project's
full history.

## 2. Collect deltas

In the **working project's** repo (not the field-notes repo), run:

```bash
git diff <last-commit>..HEAD -- CLAUDE.md docs/
git log --oneline <last-commit>..HEAD
```

If a memory directory is in play for this project (a per-project `memory/*.md` set alongside
`CLAUDE.md`, holding distilled standing rules), also list the files in it whose modification
time is after the date of `<last-commit>`. Read every file the diff and the listing surface —
these are the candidate lessons.

## 3. Classify each candidate lesson

For every distinct claim, correction, or discovered behavior in the delta, ask one question:
**"would this bite a stranger's project?"**

- **Skip** (project decision, not platform truth): schema/table/column names, screen or
  component names, business rulings ("we decided X because our data looked like Y"), seed-data
  facts, environment IDs, tenant or org identifiers, anything that only makes sense with
  knowledge of this specific app's data model.
- **Harvest** (platform truth): tool or MCP-server behavior, compiler/service semantics, API
  contracts, delegation rules, control/PCF binding facts, metadata operation quirks — anything
  that would reproduce identically in a different Power Platform project with different table
  and screen names.

A lesson can be mixed — strip the project-specific noun and check whether a generic rule
remains. If it does, that generic remainder is what gets harvested; the project-specific
wrapping is discarded.

## 4. Route each platform truth to its skill

Match the lesson to exactly one target skill by subject:

| Lesson is about | Target skill |
|---|---|
| Canvas authoring/deploy tooling, compile/sync write semantics, session pairing, verifying what actually landed, player vs. Studio verification | `canvas-deploy-safety` |
| Power Fx formula behavior, delegation, UDF/named-formula rules, runtime-only failures, write/Patch/IfError shapes | `powerfx-fieldguide` |
| PCF code components, Creator Kit controls, component property/dataset binding, canvas-component authoring mechanics | `pcf-kit-bindings` |
| Dataverse schema/metadata operations, relationships, alternate keys, choices, migration scripting patterns | `dataverse-metadata-ops` |

If a lesson genuinely spans two skills, split it: write the mechanism-specific half into each
relevant skill, cross-referencing the other skill by name rather than duplicating its content.

## 5. Corrections outrank additions

Before drafting a new bullet, search the target skill's `SKILL.md` and its `references/*.md`
files for an existing rule the new lesson contradicts, refines, or supersedes.

- **Found:** rewrite that rule **in place** — same location, updated text, updated evidence
  stamp. Never leave the old wording standing beside the new one; a reader who hits the
  superseded version first will act on stale advice.
- **Not found:** this is a genuine addition — proceed to draft it as new content in the
  appropriate section (or a new section, if none fits).

## 6. Draft the entries

Write each addition or correction in the field-notes house format: **symptom → rule → why**, in
one breath — the reader arrives with a symptom, not a rule name. Give every non-obvious rule a
dated evidence stamp, e.g. `(player-proven 10 Aug 2026)`, sourced from the working project's own
dates (commit dates, journal entry dates, or the date recorded in a memory file).

Genericize as you write, not after:

- No project identifiers — no real table/column/screen/component/variable names, no tenant or
  environment names, no business rulings. Use placeholders (`cmpX`, `scr_Example`, `MyTable`,
  `MyColumn`) the same way the existing skills do.
- Keep the source's final, corrected claim. If the working project's own notes show a rule being
  stated, then retracted, then restated correctly, harvest only the last corrected form — never
  a version the source itself walked back.

Run the leakage check before presenting anything:

```bash
~/Development/power-platform-field-notes/scripts/check.sh
```

If it fails on a leakage grep hit, generalize the flagged line (keep the evidence stamp, drop
the project-specific noun) and re-run until it prints `check.sh: OK`.

## 7. Present the batch for approval

Show the user the full batch before touching any skill file. For each drafted rule, present:

- **Target skill** (from step 4)
- **Add or correct** (from step 5) — if correct, show the old text being replaced
- **The exact text** to be written, in its final symptom → rule → why form with evidence stamp

Apply to the skill files only the rules the user approves. Discard or revise the rest per their
feedback. Do not silently drop a rule the user didn't comment on — confirm scope before writing.

## 8. Record and commit

After the approved edits are written to the field-notes repo:

1. Append one row to `HARVEST-LOG.md`: date, source project (name), the commit hash harvested up
   to (the working project's current `HEAD` at harvest time), and the skills touched.
2. Re-run `scripts/check.sh` and confirm `check.sh: OK`.
3. Commit the field-notes repo (not the working project) with a message summarizing what was
   harvested and from where, e.g.:

   ```bash
   cd ~/Development/power-platform-field-notes
   git add -A
   git commit -m "harvest: <n> lessons from <project> up to <short-sha>"
   ```

The working project's own `CLAUDE.md`/`docs/`/memory files are read-only inputs to this
workflow — this skill never edits the working project.

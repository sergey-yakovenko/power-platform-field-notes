---
name: powerfx-fieldguide
version: 0.1.0
description: Power Fx correctness rules that no static checker enforces - runtime bombs, the only working error-handling shape for writes, and delegation as schema design. USE WHEN writing or reviewing Power Fx formulas, Patch/Remove/write logic, IfError handling, choice-column comparisons, App.Formulas / named formulas / UDFs, or when chasing delegation warnings or values that render blank at runtime. DO NOT USE WHEN the question is about control properties or PCF bindings (use pcf-kit-bindings) or about deploying YAML (use canvas-deploy-safety).
author: Sergey Yakovenko
---

# Power Fx Field Guide

Power Fx has three static gates — the compile service, App Checker, and the Studio client's
own checker — and all three will happily pass a formula that dies the moment it actually runs
against real data. None of them execute the formula; they only type-check it. Treat a green
compile as "syntactically plausible," never as "correct."

## 1. Runtime is the final checker

**A formula is verified only when it has executed in the player against real data — not when
it compiles, not when App Checker is silent, not when Studio's client shows zero errors.**
Every rule in this guide was found by a formula that had been sitting compile-clean, often for
days, until a screen first called it and it either threw at runtime or rendered blank with no
diagnostic anywhere. A named formula or UDF with no live caller yet is unverified by
definition — a clean compile only proves the parser and type-checker are satisfied, and neither
of those executes a `Value()` call, walks a lookup at runtime, or evaluates a `Switch` arm.

Corollary for review: when you're asked whether a batch of App.Formulas changes is "done,"
the honest answer names which of them have a live caller that has actually rendered in the
player, and treats the rest as open.

## 2. The top runtime bombs

The full catalog, with symptoms, fixes and evidence dates, is in
`references/runtime-bombs.md`. The two most expensive to rediscover:

- **`Value(<choice>)` fails at runtime** — even on a member constant like
  `Value(MyChoice.Accepted)` — with a "cannot convert the value to a number" error that no
  static check catches. Fix: named-formula integer constants that mirror the choice's real
  option values, plus `Switch` on member equality — comparing a choice to a choice member is
  the one operation that's universally supported `(player-proven 5 Aug 2026)`.
- Writes have exactly one working error-handling shape — the **capture pattern** — and all
  three shapes that look reasonable are broken. See `references/write-patterns.md`.

Also in the catalog: a create-Patch that includes a status/state field silently no-ops the
*entire* Patch; a parenthesized `;` chain inside a `Switch`/`If` arm compiles clean and
silently never runs; the blank-record family (a blank record passed as a record-typed UDF
argument, a PK read off a not-yet-clicked selection, `IsBlank()` vs `= Blank()` on a lookup);
`[@'Name']` shadowing when a choice and a column share a display name; and grid-cell /
`ItemDisplayText` formulas running a restricted function whitelist that silently renders blank
for anything outside plain field access, one-hop lookup navigation, `If` and `&`.

## 3. Delegation is schema design

Delegation warnings are not a formula-tuning problem — they are what tells you the schema (or
the table shape you're feeding a list) needs to change. Full catalog and the testing procedure
are in `references/delegation.md`. The rules that generalize:

- **One hop to a primary key delegates. Record equality does not compile.** Two hops through a
  lookup are unfixable in Power Fx — denormalize the field onto the child table, and remember
  that nothing maintains a denormalized column for free; something (a business rule, a plugin)
  has to set it on create/update or it silently drops rows from every downstream count.
- **Compare a choice column to a choice member, never `Value()`, inside a filter predicate.** A
  choice is not a valid UDF parameter type, so this means one function per status rather than a
  parameterized one.
- **The only delegable shape for feeding a list is genuinely raw** — the data source itself, or
  `Filter`/`Sort`/`Search`/`LookUp` over it with no shaping wrapper. `ShowColumns`, `AddColumns`,
  `RenameColumns` and `ForAll` are all in the same non-delegable class — none of them delegate,
  regardless of how trivial the shaping looks.
- **Absence of a delegation warning proves nothing.** Confirm delegability by setting the app's
  data row limit to 1 and comparing row counts between the shaped and raw versions, and by
  confirming server-side paging on the wire.

## 4. Architecture rules

- **Business logic lives in named formulas and UDFs in App.Formulas, never in a control
  property.** Rules that must hold regardless of which screen or control triggers them —
  approval separation-of-duties, staleness checks, validity checks — duplicated across control
  properties drift, and the honest audit answer becomes "it depends which screen you looked
  at."
- **No `ClearCollect` caches of a Dataverse table for read-only data.** A cached collection goes
  stale the moment the underlying table changes, and it hides delegation limits that a live
  query would have surfaced.
- **A clean `App.Formulas` compile is not settled until every named formula has a live
  caller.** A compile reporting 0 errors and 0 warnings, followed by wiring one caller into a
  formula that had none, can turn into new delegation warnings on the very next compile — an
  unreferenced formula isn't analyzed as hard as a called one.

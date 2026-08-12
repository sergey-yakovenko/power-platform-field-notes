# Contributing

## Distillation Bar

The field-notes extension carries **platform truths only**—knowledge that would bite a stranger's project, not project-specific context. Every contribution must pass these gates:

### Platform Truths Only

Would this rule apply to someone else's Power Platform build? If it depends on project specifics (custom table names, role assignments, design choices), it stays internal. If it's a universal property of Dataverse, Canvas Apps, Power Fx, or the Creator Kit, it belongs here.

### Symptom-First Phrasing

Lead with the visible problem, then state the rule, then explain why. Format: "**When X happens, do Y because Z.**" This makes the guide searchable by symptom and teaches reasoning, not just procedures.

*Example (good):* When a ModernDatePicker defaults to today despite being unset, author `DefaultDate: =Blank()` because the control commits today's date on every save without an explicit blank.

*Example (bad):* Always set DefaultDate to blank.

### Volatile Facts Become Procedures

Measured values, environment-specific paths, version numbers, and dated empirical findings belong in procedures, not rules. Record "how to check" (a command, a query, a test), never fixed values like "the max row count is 2000" or "kit v1.1.41 is installed."

*Example:* Instead of "FluentDetailsList requires six property-sets," document the command to read the manifest and extract required ones.

### Dated Evidence Stamps

When a rule contradicts an earlier understanding, or when a finding took significant debugging to reach, timestamp it with the discovery date. This helps readers understand confidence and whether the finding still holds.

*Format:* `(Verified 4 Aug 2026: three real compiles, player-proven)` or `(Corrected 5 Aug — earlier claim was wrong; the property **is** delegable.)`

### Corrections Outrank Additions

When a new lesson contradicts an existing rule, rewrite the rule in place rather than appending a caveat beside it. An obsolete rule next to a correct one is worse than silence—the reader picks the wrong one. Delete the old rule and write the corrected version.

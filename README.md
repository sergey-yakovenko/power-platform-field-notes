# power-platform-field-notes

Field-tested corrections and hard-won rules for Power Platform / Dataverse / Canvas App development. This plugin extends the stock `canvas-apps` and `dataverse` plugins with platform truths distilled from a real production build—patterns that survived the gauntlet of compilation, player verification, and live environment challenges.

## Skills

- **canvas-deploy-safety** — safety protocol for writing to a canvas app through the canvas-authoring MCP: compile/write semantics, session-pairing protocol, paste-deploy fallback, player verification.
- **powerfx-fieldguide** — Power Fx correctness rules no static checker enforces: runtime bombs, the capture pattern for writes, delegation as schema design.
- **pcf-kit-bindings** — binding contracts and authoring rules for Creator Kit / PCF code components and canvas components.
- **dataverse-metadata-ops** — safety rules for Dataverse schema changes and idempotent migration scripts.
- **pp-harvest** — maintenance workflow: harvest new lessons from a working project into these skills.

## Installation

```bash
/plugin marketplace add /Users/smpobox/Development/power-platform-field-notes
/plugin install field-notes@power-platform-field-notes
```

Once the repository is pushed to GitHub, use:

```bash
/plugin marketplace add <git-url>
/plugin install field-notes@power-platform-field-notes
```

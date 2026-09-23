---
description: "Propose promoting durable session-log entries into permanent project memory"
---

Review `docs/session-log.md` and PROPOSE (do not apply without user
confirmation) which entries should be promoted into permanent memory:

- `AGENTS.md` — recurring rules, environment facts, real commands
- `openspec/config.yaml` — project context block or per-artifact rules
- openspec specs / changes — behavior already implemented but still
  uncovered by a spec

Workflow:

1. Read `AGENTS.md`, `docs/session-log.md` and `openspec/config.yaml`.
2. For each journal entry, decide where (or whether) it should live
   permanently, and propose the exact text to add.
3. Show the proposed edits (target files + content) and WAIT for the
   user's approval.
4. After approval: apply the promotions, then REMOVE the absorbed
   entries from `docs/session-log.md`.
5. Summarize what moved and what remains in the journal.

Eligibility: only entries that follow the journal rules (verified by
execution or source reading). Never promote anything else.

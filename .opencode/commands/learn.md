---
description: "Record verified session learnings into docs/session-log.md"
---

Review the current chat session and append to `docs/session-log.md`
every fact that is BOTH **new and verified** (by execution or source
reading): API signatures discovered, pitfalls, reproduced failures.

Rules:

- Only append facts verified during this session; never record
  hypotheses or opinions.
- Do not duplicate facts already present in the journal.
- One entry per fact: date payload - fact - verification source
  (command run or file/line read).
- Preserve the file's existing structure (header, maintenance rule,
  dated sections).
- If nothing qualifies, say so explicitly and change nothing.
- Do not edit AGENTS.md, openspec/config.yaml or openspec artifacts:
  promoting durable entries is `/consolidate`'s job, not `/learn`'s.

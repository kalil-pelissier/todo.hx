# docs/session-log.md — session journal

Record here ONLY facts that are new and verified (by actual execution
or source reading): API signatures discovered, pitfalls, reproduced
failures. No untested hypotheses, no opinions — decisions belong in
the openspec change's `design.md`, durable memory in `AGENTS.md` /
`openspec/config.yaml`.

## Maintenance rule

- One entry per fact: date - fact - verification source (command run,
  file/line read).
- At the end of a session: run `/learn` to append the verified facts.
- At the start of a session: run `/consolidate` to propose promoting
  durable entries into AGENTS.md / openspec/config.yaml, then remove
  absorbed entries from the journal.

## 2026-09-22

- `steel-docs.md` from `steel-event-system` (commit 09d67dfe7) does
  not list `query-document`, `string->tsquery`, `tsquery-loader`,
  `editor-count` (grep = 0 occurrences) although the vendored
  `treesitter.scm` and `editor.scm` export them — verified against the
  copies in `docs/vendor/` on this date. Prescribed rule: trust the
  vendored `.scm` over the generated docs (see
  `docs/vendor/README.md`).
- `scripts/gen-api-index.sh` regenerates `docs/api-index.md`
  idempotently — identical md5 on a double run (b09432ee...), 407
  symbols across the 10 modules.

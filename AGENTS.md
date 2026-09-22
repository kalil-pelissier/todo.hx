# AGENTS.md — todo.hx

Helix plugin in Steel/Scheme: navigation between structured @info tags
(TODO, NOTE, PERF, ...) inside comments, through the injected
tree-sitter "comment" grammar and Steel's `query-document` pipeline.

## Where to look

- **Steel API**: `docs/api-index.md` (generated index of 407 symbols)
  and full sources in `docs/vendor/` (`STEEL.md`, `steel-docs.md`, the
  10 `helix/*.scm` modules) — provenance and caveats in
  `docs/vendor/README.md`
- **Project conventions**: `openspec/config.yaml` (context + rules)
- **System state** (expected behavior): `openspec/specs/comment-tag-navigation/spec.md`
- **Raw session journal**: `docs/session-log.md`
- **Detailed technical pipeline** (detection, loader, navigation,
  pitfalls): `ARCHITECTURE.md`

## Real commands

- Reload the plugin in Helix:
  `cp navigation.scm ~/.local/share/steel/cogs/todo.hx/navigation.scm`
  then **restart Helix** (a function only becomes a `:xxx` command if
  it is `provide`d in the user's `~/.config/helix/helix.scm`).
- Build/deploy: `forge install todo.hx` (the cogs directory above must
  then be up to date).
- Tests: no automated test suite — manual verification in Helix
  (scenarios in ARCHITECTURE.md); check paren balance of any modified
  `.scm`.
- Regenerate the API index: `./scripts/gen-api-index.sh`.

## Rules

**Never write a call to a helix/* function that does not appear in
docs/api-index.md; when in doubt, open the corresponding .scm in
docs/vendor/ — never guess a signature.**

For any new feature: go through `/opsx-propose` before writing code.

## Session memory

- `/learn` — at the end of a session, record facts that are **new and
  verified** (API signatures discovered, pitfalls, reproduced
  failures) into `docs/session-log.md`.
- `/consolidate` — propose promoting durable journal entries into
  `AGENTS.md` / `openspec/config.yaml`, then remove absorbed entries
  from the journal.

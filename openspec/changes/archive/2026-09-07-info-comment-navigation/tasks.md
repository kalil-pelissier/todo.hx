## 1. Spikes (verify Steel API behavior before building)

- [x] 1.1 Spike: `query-document` DOES traverse injected layers automatically in theory (`run_query` at `extensions.rs:184-253` iterates layers via `injections_at_byte_idx`). **However**, the `tsquery-loader` boxed Steel callback runs on a forked thread (`vm.rs:1713`) without the `CONFIG` context, so `string->tsquery` cannot resolve the "comment" language grammar from inside the callback. Pre-compiling at module load time also failed — the boxed function could not return the `TSQuery` custom type back to Rust. Diagnostic: `query-document` ran but `all-captures=0`. **Approach B rejected; pivoted to Approach A.**
- [x] 1.2 Spike: `rope-regex` (`extensions.rs:865`) supports `\b` word boundaries via `regex_cursor`. Pre-compile with `(text.rope-regex "\\b(TODO|NOTE|INFO)\\b")` at module load; test with `(text.rope-regex-match? regex slice)`. No context issues — runs in the normal CTX path.
- [x] 1.3 Spike: `goto-line` expects **1-indexed** line numbers (`commands.rs:goto_line_without_jumplist` uses `count.get() - 1`), but `rope-char->line` and `get-current-line-number` return **0-indexed**. Fix: add `+ 1` when calling `goto-line`. Verified during manual testing — without the adjustment, cursor lands one line before the comment.

## 2. Module structure

- [x] 2.1 Create the navigation module under the package: `require`s `helix/editor.scm`, `helix/static.scm`, `helix/commands.scm`, `helix/treesitter.scm`, and `helix/core/text` (via `require-builtin ... as text.`).
- [x] 2.2 Create or update the package's `helix.scm` adapter that `require`s the navigation module and `provide`s `todo-next` and `todo-prev` at top level, so they become typed commands.
- [x] 2.3 Add `;;@doc` annotations on `todo-next` and `todo-prev` so the command palette shows help text.

## 3. Tag matching

- [x] 3.1 Pre-compile a `rope-regex` with `\b(TODO|NOTE|INFO)\b` at module load time via `(text.rope-regex ...)`. v1 is intentionally limited to these three tags.
- [x] 3.2 Implement `comment-kind?` to check `tsnode-kind` against `comment`, `line_comment`, `block_comment`, `doc_comment` — covering the common comment node names across grammars.

## 4. Core scan

- [x] 4.1 Implement `(scan-info-tag-lines doc-id)`: get rope via `(editor->text doc-id)`, get root tree via `(document->tree doc-id)` → `(tstree->root tree)`, recursively walk for comment nodes via `collect-comment-nodes`, for each comment extract rope slice via `(text.rope->slice rope start-char end-char)`, test with `(text.rope-regex-match? info-regex slice)`, convert byte→char→line for matches. Returns sorted list of `(line . byte)` pairs. _(Re-implemented with Approach A: tree walk + rope-regex, replacing the failed Approach B query-document + tsmatch-capture.)_
- [x] 4.2 Handle the "no tree-sitter parser" and "no match" cases: return an empty list silently — no error, no status message.
- [x] 4.3 Sort the byte-line pairs by line ascending; for ties (same line) preserve a deterministic order using byte offset as secondary key.

## 5. Navigation logic

- [x] 5.1 Implement `(todo-next)` body: `(editor-focus)` → `(editor->doc-id)` → `(scan-info-tag-lines doc-id)` → `(get-current-line-number)` → filter pairs with `line > current` → pick the smallest such line (tie-break by smaller byte offset matches `movement.rs:597` semantics). On empty result: return silently (cursor stays). On match: call `(jump-to-line target-line)` which does `(goto-line (+ line 1))` then `(goto-first-nonwhitespace)`. The `+ 1` converts 0-indexed line to 1-indexed for `goto-line`.
- [x] 5.2 Implement `(todo-prev)` body: same as `todo-next` but filter pairs with `line < current`, pick the largest such line (tie-break by larger byte offset matches `movement.rs:600`). On match: `(jump-to-line)`. On empty: silent.
- [x] 5.3 Verify `(goto-line N)` accepts a plain integer argument (signature is `(goto-line line [extend #false])` per `commands.scm:17-18`). Confirmed — but requires 1-indexed input; `jump-to-line` handles the conversion.

## 6. Wiring and invocation

- [x] 6.1 Re-export `todo-next` and `todo-prev` from the package's `helix.scm` via `(provide todo-next todo-prev)` so they become typed commands (`:todo-next` / `:todo-prev`) and static-bindable symbols (`'todo-next` / `'todo-prev`).
- [ ] 6.2 Confirm via `:eval-buffer` or by reloading the package that `:todo-next` and `:todo-prev` appear in the command palette with `@doc` help text. _(Requires interactive Helix session — pending manual testing.)_
- [x] 6.3 Do NOT ship any `(add-global-keybinding ...)` call. The plugin exposes symbols only — users wire `]i` / `[i` (or any keys) in their own `init.scm`.

## 7. Manual verification matrix

- [ ] 7.1 Rust buffer (gated via `rust/injections.scm`): three TODO comments at lines 10, 25, 50. Cursor at line 1, invoke `:todo-next` → expect cursor at line 10 (first non-whitespace). Invoke `:todo-next` again → line 25. Again → line 50. Again → cursor stays at 50, no message. _(Requires interactive Helix session.)_
- [ ] 7.2 Same buffer, cursor at line 50, invoke `:todo-prev` three times → expect lines 25, 10, then stays at 10 silently on third invocation. _(Requires interactive Helix session.)_
- [ ] 7.3 Python buffer with `# TODO:`, `# NOTE:`, `# INFO:` comments. Invoke `:todo-next` repeatedly → expect jumps across all three tags (verifies the full `@info` set, not just `TODO`). _(Requires interactive Helix session.)_
- [ ] 7.4 Plain-text buffer with `// TODO: foo` (no tree-sitter parser). Invoke `:todo-next` → expect cursor does not move and no status message (matches "buffer with no tree-sitter parser" scenario). _(Requires interactive Helix session.)_
- [ ] 7.5 Empty buffer. Invoke `:todo-next` → expect cursor does not move and no status message (matches "no match in empty buffer" scenario). _(Requires interactive Helix session.)_
- [ ] 7.6 Buffer with comments that contain no `@info`-level tag (e.g. `// hello`, `// world`). Invoke `:todo-next` → expect cursor does not move, no message (matches "no match in buffer with comments but no info tags" scenario). _(Requires interactive Helix session.)_
- [ ] 7.7 Buffer with two `@info` captures on the same line (e.g. `// TODO: fix NOTE: remember`). Invoke `:todo-next` → expect cursor lands on that line (same-line disambiguation deferred to v2; cursor lands, does not fail). _(Requires interactive Helix session.)_
- [ ] 7.8 Indented TODO comment (e.g. inside a nested block with `    // TODO: fix`). Verify cursor lands on the first non-whitespace character of the target line (the `/`), not at column 0 (matches "cursor lands on first non-whitespace character" scenario). _(Requires interactive Helix session.)_
- [ ] 7.9 Side-effect check: invoke a Helix search (`/`) first to populate the `/` register, then invoke `:todo-next`. Verify `/` register content and `last_search_register` are unchanged afterward, and the user's selection state is unchanged (matches "registers and search state preserved" scenario). _(Requires interactive Helix session.)_
- [ ] 7.10 Static-binding check: add `(add-global-keybinding (hash "normal" (hash "]i" 'todo-next)))` to `init.scm`, restart Helix, press `]i` in normal mode in a Rust buffer with TODOs → expect same behavior as `:todo-next` (matches "bound to a custom key" scenario). _(Requires interactive Helix session.)_

## 8. Documentation

- [x] 8.1 Update `README.md` with: feature summary (navigation to info-level comment tags via `]i`/`[i`), list of recognized tags (reference Helix's `@info` set), suggested keybinding snippet for `init.scm`, and the limitation note (requires tree-sitter parser + comment injection; buffers without a parser silently no-op).
- [x] 8.2 Note in README that v2 may extend to `@warning` / `@error` / `@hint` navigation under the reserved `]w` / `]E` / `]h` namespace.
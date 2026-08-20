## Why

Helix highlights TODO/FIXME-class tags via a tree-sitter injection query (`comment/highlights.scm`), but provides no way to *jump* between them. Users must manually scroll or use generic `search` to move across TODO comments in a buffer. This plugin adds `]i`/`[i` (or `:todo-next`/`:todo-prev`) navigation that mirrors the existing `goto_next_comment`/`goto_prev_comment` motion family — but targets only info-level comment tags rather than all comments.

## What Changes

- Add `todo-next` and `todo-prev` functions (Scheme) that jump the cursor to the nearest info-level comment tag in the current buffer.
- Walk the document's root tree-sitter tree (via `document->tree` → `tstree->root` → recursive `tsnode-children`) to find comment nodes (`line_comment`, `block_comment`, `comment`, `doc_comment`), then match their rope text against a pre-compiled `rope-regex` with `\b(TODO|NOTE|INFO)\b` word boundaries — no false positives from substrings.
- v1 is intentionally limited to TODO, NOTE, and INFO tags. The full `@info` set from `comment/highlights.scm` (PERF, OPTIMIZE, PERFORMANCE, QUESTION, ASK, REVIEW, PR, CR, TO-DO) can be added in a point release.
- Match the behavior of `goto_next_comment` (`commands.rs:6230`, `movement.rs:563`): strict `>`/`<` comparison, tie-break by wider span, no wrap-around, silent no-match (cursor stays put).
- Place the cursor at the first non-whitespace character of the target line via `goto-line` (1-indexed, adjusted from `rope-char->line`'s 0-indexed output) followed by `goto-first-nonwhitespace`.
- Expose both commands as typable (`:todo-next` / `:todo-prev`) and as static-bindable symbols (`'todo-next` / `'todo-prev`); ship no default keybinding — users wire their own via `add-global-keybinding`.
- Suggest `]i` / `[i` in the README (free in Helix's default keymap; mnemonic for `@info`).

## Capabilities

### New Capabilities
- `info-comment-navigation`: jump the cursor to the nearest info-level comment tag (TODO, NOTE, INFO) in the current buffer, in both forward and backward directions.

### Modified Capabilities
<!-- None — no existing specs in openspec/specs/. -->

## Impact

- **New code**: Scheme modules under the plugin package (`todo.hx`) — a `helix.scm` adapter that `provide`s `todo-next`/`todo-prev`, plus a navigation module implementing the tree walk + regex match + jump logic.
- **Dependencies**: relies on the Steel plugin API (`helix/editor`, `helix/commands`, `helix/static`, `helix/treesitter`, `helix/core/text`) and Helix's tree-sitter parsing (requires a grammar with comment nodes). No new Rust code, no tree-sitter queries authored.
- **No side effects on editor state**: the only mutation is cursor position via `goto-line`; no registers, selections, or search state touched.
- **Limitation**: requires a tree-sitter parser for the current buffer. Buffers without a parser silently do nothing — no fallback, no message. Matches the precedent of `goto_next_comment`, which sets "Syntax-tree is not available in current buffer" but otherwise stays put.
- **Out of scope (deferred to v2)**: multi-buffer/project-wide navigation, custom picker UI, count argument support, `@warning`/`@error`/`@hint` navigation, configurable tag set, message-on-no-match option, multiple info tags on the same line, using `query-document` + `tsmatch-capture` (blocked by Steel FFI context issue — see design.md).
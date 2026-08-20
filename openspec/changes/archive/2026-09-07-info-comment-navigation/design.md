## Context

Helix's editor ships a Steel Scheme interpreter (`helix-term/src/commands/engine/steel/`) that lets plugins query the editor and run commands. The Steel tree-sitter module (`treesitter.scm`) exposes a query pipeline and tree-walking primitives.

The relevant existing primitives:

- **Tree-sitter tree access**: `document->tree` (`mod.rs:3764`) returns the root `TSTree` for a document's parsed syntax tree. `tstree->root` (`treesitter.scm:56`) gets the root `TSNode`. `tsnode-children` / `tsnode-kind` / `tsnode-start-byte` (`treesitter.scm:78,134,204`) walk and inspect nodes.
- **Rope API**: `editor->text` (`mod.rs:1523`) returns the document rope. `rope->slice` (`extensions.rs:957`) extracts a sub-rope by char index. `rope-byte->char` / `rope-char->line` (`extensions.rs:979,1013`) convert offsets. `rope-regex` / `rope-regex-match?` (`extensions.rs:865,890`) compile and test regex against ropes with `\b` word-boundary support.
- **Cursor motion**: `goto-line` (`commands.scm:17`) lands the cursor at a 1-indexed line; `goto-first-nonwhitespace` (`static.scm`) moves it to the first non-whitespace character.
- **Position queries**: `editor-focus` → `editor->doc-id` for the current document; `get-current-line-number` (`mod.rs:667`) returns the cursor's 0-indexed line.
- **Ancestor behavior**: `goto_next_comment` (`commands.rs:6230`) delegates to `goto_ts_object_impl` → `movement::goto_treesitter_object` (`movement.rs:563`), which selects the nearest comment node via strict `>` / `<` byte comparison with tie-break by wider span. No wrap, silent on no-match.

The plugin is packaged via `cog` (`cog.scm`) and run by Helix's Steel runtime loading its `helix.scm`, which `provide`s the user-callable commands. See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Walk the root tree-sitter tree to find comment nodes, then match info-level tags (TODO, NOTE, INFO) via word-boundary `rope-regex` — no false positives from substrings.
- Match `goto_next_comment` behavior for boundaries, wrap, silence, and direction comparison (strict, tie-break by wider span).
- Expose the commands in both invokable forms (typable `:todo-next` and static-bindable `'todo-next`) without grabbing any default keybinding.
- Keep editor state untouched except for cursor position.

**Non-Goals:**
- Do not implement `@warning`, `@error`, or `@hint` navigation in v1 (deferred to v2; `]w` / `]E` / `]h` namespace reserved).
- Do not implement cross-buffer/project navigation — only the current buffer.
- Do not implement a custom picker UI (component stack is available but overkill for v1).
- Do not implement count-argument support (`3]i` to jump three tags).
- Do not ship a default keybinding. The plugin exposes the symbol; users bind `]i` / `[i` (or any key) in their own `init.scm`.
- Do not emit any status message on no-match (matches `goto_next_comment`'s silence).
- Do not resolve the "two `@info` captures on the same line" edge case beyond guaranteeing the cursor lands on that line.
- Do not use `query-document` / `tsquery-loader` / `tsmatch-capture` — the Steel boxed-callback FFI cannot reliably return a pre-compiled `TSQuery` to Rust's `run_query` (verified during implementation; see Decision 1).

## Decisions

### Decision 1: Walk root tree + rope-regex word-boundary match (Approach A)

**Choice**: Walk the document's root tree-sitter tree (via `document->tree` → `tstree->root` → recursive `tsnode-children`) to find comment nodes (`line_comment`, `block_comment`, `comment`, `doc_comment`). For each comment node, extract its rope slice and test against a pre-compiled `rope-regex` with `\b(TODO|NOTE|INFO)\b` — word-boundary matching prevents false positives (e.g. "TODO" inside "autodocString").

**Alternatives considered**:
- **Approach B** (query-document + tsmatch-capture on `comment/highlights.scm` `@info`): run Helix's stock comment highlights query against injected layers via `query-document` + `tsquery-loader`. **Tested and rejected**: the `tsquery-loader` boxed Steel callback runs on a forked Steel thread (`vm.rs:1713-1726`) where the `CONFIG` context (`*helix.config*`) is unavailable. `string->tsquery` requires `CONFIG` to resolve the "comment" language grammar (`mod.rs:3886-3899`). Pre-compiling the query at module load time and returning it from the callback also produced zero captures — the boxed-function marshalling could not reliably return the `TSQuery` custom type back to Rust's `TreeSitterQueryLoader::load` (`extensions.rs:109-129`). Diagnostic confirmed: `query-document` ran but `all-captures=0`.
- **Custom query with `#match?`**: ship a per-language query that predicates on `TODO`. Rejected because per-language enumeration doesn't scale to all Helix-supported languages; raising regex flavor quirks across tree-sitter builds.

**Rationale for A**: the root tree walk is the same approach `goto_next_comment` uses (`movement.rs:563`), and `rope-regex` with `\b` word boundaries gives precise tag matching without the FFI issues. The trade-off is a hardcoded tag list — but v1 is intentionally limited to TODO, NOTE, INFO. The full `@info` set can be added later or v2 can revisit Approach B if the Steel FFI is fixed.

### Decision 2: Convert comment node byte to line; goto-line expects 1-indexed

**Choice**: Take each comment node's start byte offset (from `tsnode-start-byte`), convert to char via `rope-byte->char`, then to line via `rope-char->line` (both 0-indexed), then `(goto-line (+ line 1))` + `(goto-first-nonwhitespace)`. The `+ 1` is required because `goto-line` uses `count.get() - 1` internally (`commands.rs:goto_line_without_jumplist`), expecting 1-indexed input.

**Alternatives considered**:
- **Walk up to the comment node via `tsnode-parent`**: would put the cursor at the *comment*'s start (e.g. the `//`), matching `goto_next_comment`'s exact column. Adds complexity (parent-walking through the injected "comment" grammar tree to the host-language comment node) for a small column difference.
- **Position cursor directly via byte offset**: would land on the "T" of "TODO" itself. Requires a Steel API we have not verified to set an absolute cursor position; `goto-line` is the confirmed path.

**Rationale**: simplicity. `goto-line` + `goto-first-nonwhitespace` lands at the first non-whitespace char of the target line — visually identical to `goto_next_comment` for the user's purposes (both point at the comment, not at leading whitespace). The 1-indexed adjustment was discovered during manual testing (cursor was landing one line before the comment).

### Decision 3: Line-based comparison rather than byte-based

**Choice**: Convert all matched comment nodes to line numbers (0-indexed), then pick the nearest target line strictly greater (next) / less (prev) than the cursor's current line (also 0-indexed from `get-current-line-number`). The `+ 1` adjustment happens only at `goto-line` call time.

**Alternatives considered**:
- **Byte-exact comparison like `movement.rs:594-601`**: would track byte offsets and tie-break by wider span. Lets us handle the "same line, different column" case (`@info` capture at column 5 vs column 30 of one line). But `goto-line` only takes a line number — column-aware jumping requires a different cursor primitive (`set-current-selection-object!` + `push-range-to-selection!` in `static.scm`), which is more code for v1.

**Rationale**: pending v2 design for the two-captures-same-line case, line-based comparison is sufficient and matches the user-visible behavior of `goto_next_comment` (which, after all, also lands the cursor on a line — the user does not perceive byte offsets). Tie-break by wider span is preserved at the byte-record level so we always pick a deterministic target line even when multiple captures share it.

### Decision 4: Static-primary, typable free; no default keymap shipped

**Choice**: `provide` both `todo-next` and `todo-prev`. Both work via `:todo-next` typable invocation AND as `'todo-next` symbols in user keymaps. The plugin ships no `(add-global-keybinding ...)` call. The README suggests `]i` / `[i` as a snippet the user pastes into their `init.scm`.

**Alternatives considered**:
- **Ship `]i` / `[i` as defaults**: more opinionated. Could collide if a user has already bound `]i` to a custom macro. Rejected: plugins shouldn't fight the user's keymap.
- **Typable-only (no static)**: matching `:buffer-next` (which is typable-only). Rejected: this is a navigation motion — muscle-memory usage is the primary use case. Static is the right primary mode; `goto_next_comment` is static-only, confirming the convention. We get both from one `provide` anyway, so typable stays free.

**Rationale**: `]i` is unbound in Helix's default keymap (verified in `default.rs:126-138`), and `i` is mnemonic for `@info` — it sits naturally next to `]c` (next comment) in the `]X` motion family. Future v2 `@warning`/`@error`/`@hint` navigation can take `]w` / `]E` (`]e` is taken) / `]h`.

### Decision 5: Match `goto_next_comment` boundary behavior (no wrap, silent)

**Choice**: no wrap-around at buffer end; silent when no match (no status, no error, cursor stays put).

**Alternatives considered**:
- **Wrap like `search`** (`search.wrap_around = true`, `commands.rs:2312-2325`): on no match forward, loop to first match; emit "Wrapped around document" status. Rejected: we explicitly model on `goto_next_comment`, not `search` — these are object motions in the `]X` family, all of which stay put silently at the boundary. Mixing the two behaviors would surprise users who already know `]c` / `]f` / `]p`.
- **Status message on no match**: "No more TODO comments". Slightly more discoverable but breaks parity with `goto_next_comment`'s silence. Rejected for v1; can be added behind a config flag in v2.

## Risks / Trade-offs

- **Hardcoded tag list** → v1 matches TODO, NOTE, INFO via `\b(TODO|NOTE|INFO)\b` regex. This duplicates a subset of Helix's `comment/highlights.scm` `@info` `#any-of?` list. If Helix adds new info tags, the plugin won't recognize them until updated. Mitigation: the tag set is small and stable; v2 can revisit Approach B if the Steel FFI is fixed, or expand the regex.
- **Root tree walk instead of injected comment layers** → we walk the host language's root tree for comment nodes (`line_comment`, `block_comment`, etc.) rather than the injected "comment" grammar tree. This means we match the *full comment text* against the regex, not the structured `(tag (name))` nodes. Trade-off: the regex handles word boundaries correctly, but we lose the structural precision of the comment grammar. Acceptable for v1.
- **`rope-regex` word-boundary on non-ASCII** → the `\b` anchor in `regex_cursor` operates on word characters (ASCII alphanumeric + underscore). Tags are always uppercase ASCII, so this is not a concern for v1.
- **`goto-line` 1-indexed vs `rope-char->line` 0-indexed** → resolved by adding `+ 1` in `jump-to-line`. Verified during manual testing — without the adjustment the cursor lands one line before the comment.
- **Two info tags on the same line** → line-based comparison deduplicates them by line. Both matches point to the same target line, so the cursor lands there either way. The choice of which match's column to use is moot until v2 introduces column-precise landing.

## Open Questions

- **Can Approach B be made to work?** The Steel boxed-callback FFI (`#%closure->boxed-function` → `steel_function_to_arc_rust_function` at `vm.rs:1713`) forks a Steel thread without the `CONFIG` context. A future Steel or Helix update that threads the config through boxed callbacks would unblock `query-document` + `tsmatch-capture`. Not blocking for v1.
- **Full list of languages with comment nodes in the root tree** → most tree-sitter grammars name their comment nodes `line_comment`, `block_comment`, `comment`, or `doc_comment`. The plugin checks all four. Languages with non-standard comment node names won't be matched. A coverage audit is deferred.
- **Expanding beyond TODO/NOTE/INFO** → v1 is intentionally limited to these three. The full `@info` set (PERF, OPTIMIZE, PERFORMANCE, QUESTION, ASK, REVIEW, PR, CR, TO-DO) can be added to the regex in a point release.
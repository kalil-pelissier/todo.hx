# Architecture

How todo.hx detects and navigates info-level comment tags — end to end,
plus the problems encountered during development and how they were fixed.

## Big picture

```
 file.rs
    │  tree-sitter (rust grammar, root layer)
    ▼
 root layer ──rust/injections.scm──▶ injected "comment" layers
    │                               (one per // comment, non-doc)
    │                                     │  tree-sitter-comment grammar
    │                                     ▼
    │                     source = repeat(choice(tag, uri, text))
    │                       tag  = seq(name, optional(user), ":")
    ▼                                     ▼
 (scan-info-tags doc-id) ── query-document(loader, doc-id)
    │   loader: "comment" → tag query
    │           root lang → empty query (pass-through!)
    │           other     → #f
    ▼
 captures @info.tag (predicate-gated) → (start-byte . end-byte) pairs, sorted
    ▼
 (navigate-selection doc-id tags dir?)
    │   per-range: strict byte compare, count loop, directional range
    │   bridge: goto-line (pushes jumplist) then exact selection
    ▼
 exact tag range selected — head at tag end (forward) / tag start (backward)
```

## 1. Tag detection

### The comment injection model

Helix parses each buffer with the host language's grammar (the root layer).
Its `injections.scm` (e.g. `runtime/queries/rust/injections.scm`) marks every
non-doc comment node as `@injection.content` with `injection.language
"comment"`. Tree-house then parses each of those ranges with the
**tree-sitter-comment** grammar into separate injection layers.

Doc comments are different: Rust `///` comments inject `markdown-rustdoc`,
not `comment`. This is why `// TODO` is detected but `/// TODO` is not —
consistent with Helix's own tag highlighting.

### The tag grammar — the colon rule

From `tree-sitter-comment`'s grammar:

```
source = repeat(choice(tag, _full_uri, alias(_text, "text")))
tag    = seq(name, optional(_user), ":")
```

- `name` is an **external token** (a scanner heuristic recognizes uppercase
  tag-like words), and the tag only completes with a trailing `":"`.
- `STOP_CHARS` include `":"`, `"("`, `","`, `"."` … so `TODO(user):` parses
  as one tag with an optional user part.
- **Multiple tags per comment are possible** when each carries a colon:
  `// TODO: a NOTE: b` yields two `tag` nodes.
- A tag word **without** a colon (`// fix the TODO`) parses as a plain
  `text` token, not a tag.

Helix's `comment/highlights.scm` has two `@info` patterns: the structural
`((tag (name) @info) …)` and a permissive `("text" @info (#any-of? …))`
that also highlights bare tag words mid-sentence. This is why a second,
colon-less `TODO` in a comment is *highlighted* but **not navigable** by
this plugin: navigation targets structural tags only, which mirrors the
textobject-style semantics of native `]c`.

### The plugin's query

Maintained in `navigation.scm` as `tag-query-src` (see provenance note
there). One pattern:

```scheme
((tag (name) @info.name) @info.tag
 (#any-of? @info.name "INFO" "NOTE" "TODO" …))
```

`scan-info-tags` reads the `@info.tag` capture — the whole tag node's
range, used as the selection. The `@info.name` capture exists only to
feed the predicate. (During development a second, ungated
`(tag) @raw.tag` pattern served as a diagnostic baseline to separate
"no tags" from "predicate filtered everything"; it was removed with the
diagnostic in the final cleanup.)

### The loader contract — the critical detail

`query-document` walks the document's layers via a stack, asking the
loader for a query per language. In Helix (extensions.rs, `run_query`):

```rust
match query_loader.load(lang_str) {
    Ok(Some(loaded)) => query_map.insert(lang, loaded),
    Ok(None) => continue,          // ← skips this layer's injection walk
    Err(e) => return Err(e),
};
for inj in layer_data.injections_at_byte_idx(lower) { stack.push(inj.layer); }
```

Returning `#f` for a language means the walk **never descends into that
layer's injections**. A loader that only answers `"comment"` returns `#f`
for the root language (`"rust"`), so the injected comment layers are never
reached — zero captures, silently.

The fix: return a query for **every traversed language**. The root
language gets a pre-compiled **empty query** (zero patterns — valid
against any grammar, matches nothing) as a pass-through:

```scheme
(cond [(equal? lang "comment")    compiled-tag-query]
      [(equal? lang root-lang)    compiled-empty-query]
      [else #f])
```

## 2. Navigation

### Byte-position ordering

Targets are `(start-byte . end-byte)` pairs sorted by start byte, compared
against the cursor's byte (the selection head, converted char→byte).
Mirrors `movement::goto_treesitter_object`:

- forward: smallest `start-byte` strictly **greater** than the cursor byte
- backward: largest `end-byte` strictly **less** than the cursor byte
- deterministic tie-breaks, no wrap-around, silent on no-match

### Directional selections

- forward: `range(start-char, end-char)` — anchor at tag start, head at end
- backward: `range(end-char, start-char)` — head at tag start

### Count

Each range advances through `count` successive targets independently
(`(editor-count)`, so `3]i` with a keybinding jumps three tags). Iteration
resumes strictly beyond the current target (end byte forward, start byte
backward), matching the native `for _ in 0..count` loop.

### Multi-cursor

`navigate-selection` transforms **every** range of the current selection:
ranges with a target become the exact tag range, ranges without keep their
value, and the primary index is restored after committing. Committing uses
`set-current-selection-object!` for the first range and
`push-range-to-selection!` for the rest (Helix's `Selection::push`
normalizes/sorts).

### Jumplist bridge

Steel does not expose Helix's internal `push_jump`. The bridge: Steel's
`goto-line` implementation (helix-term mod.rs, `goto_line_impl`) calls
`push_jump` **unconditionally** before moving the cursor. So
`navigate-selection` calls `goto-line` to the primary target's line (which
records the pre-motion selection in the jumplist), then immediately
replaces the throwaway movement with the exact per-range tag selections.
`<C-o>` therefore returns to the pre-motion selection.

## 3. Problems encountered and fixes

| # | Problem | Fix |
|---|---------|-----|
| 1 | `format` / `number->string` absent from the Steel prelude (load error) | `string-append` + qualitative counts (`count-status`: "0"/"1"/"2+") |
| 2 | Identifiers must be defined before use in Steel modules (`filter-map`, `sort-tag-pairs` free-identifier errors) | Reordered: utilities before users |
| 3 | `helix.editor-count` free identifier — `helix/editor.scm` is required *unprefixed* | Bare `editor-count` |
| 4 | `:todo-diagnostic` invisible — a Steel function only becomes a `:command` when `provide`d at the top level of the user's `~/.config/helix/helix.scm` | Added to the user's provide list |
| 5 | **Zero captures from `query-document`** — the loader contract above | Empty-query pass-through for the root language |
| 6 | `document->tree-byte-range` resolved the root layer for a comment range — `layers_for_byte_range` requires the injection to contain **both** bounds and layer ranges are `[start, end)` (exclusive end) | Pass an interior byte `(s, s)` instead of `(s, e)` |
| 7 | Paren imbalance in `transform-range` (one extra `)`) | Removed; a balance checker now validates the file |
| 8 | Wrong mental model: "one tag per comment" | Corrected: the colon rule — see §1 |

Note on #5: the archived v1 design concluded the Steel boxed-callback FFI
could not return a compiled `TSQuery`. The v2 diagnostic disproved this —
the boxed callback works fine (its calls were traced through a mutable
`box` across the forked-thread boundary). The real cause of v1's
`all-captures=0` was the loader contract; v1 never got far enough to hit it
twice.

## 4. Why the query is a maintained copy

The plugin's query mirrors the `@info` vocabulary of Helix's
`runtime/queries/comment/highlights.scm` but cannot reuse that file at
runtime:

1. **Steel plugins have no filesystem access.** The Helix Steel
   environment exposes ~870 functions (see `steel-docs.md`); none read
   files. The only non-Helix builtin modules are `steel/random` and
   `steel/time`.
2. **There is no stable on-disk path anyway.** Helix resolves its runtime
   through a five-level fallback chain (CARGO_MANIFEST_DIR sibling →
   config dir → `HELIX_RUNTIME` → `HELIX_DEFAULT_RUNTIME` →
   executable-sibling). On this machine it happens to be
   `~/.cargo/bin/runtime/`; a distro build uses a different level.
   Replicating that internal chain in a plugin would couple it to
   non-public internals.
3. **The file is not usable verbatim.** `highlights.scm` captures `@info`
   on the `name` node; navigation needs the whole `tag` node's range as
   the selection. Reuse would require string-transforming a query file —
   fragile parsing of a non-API artifact.
4. **It contains patterns we deliberately do not want**, notably
   `("text" @info …)`, which would turn bare mid-sentence tag words into
   navigation targets — a behavior change from what was specified and
   tested.

The trade-off is vocabulary drift, which is bounded (the `@info` list is
stable) and manageable: `navigation.scm` carries a provenance comment
pointing at the source file to sync from, and a dev-time check can compare
the two lists without any runtime coupling.

## 5. Limitations

- Requires a tree-sitter parser **and** a `comment` injection for the
  buffer's language; otherwise silent no-op.
- Tags in doc comments (`/// TODO` in Rust) are not detected: doc comments
  inject `markdown-rustdoc`, not `comment`.
- Only structural tags (trailing colon) are navigable; bare tag words
  highlighted by Helix's permissive `("text" @info)` pattern are not.
- Current buffer only.

## 6. Open observation

During development, the (now-removed) diagnostic's layer stage — the
Path B feasibility check — reported `inj=rust` on Helix 25.07.1 even
though the loader trace proved comment layers existed and the production
`query-document` pipeline found them. `document->tree-byte-range(s, s)`
resolving to the root layer there was never explained. It only affected
the diagnostic (the production code never resolves layers by byte range)
and became moot once the query pipeline was validated, but it is
recorded here for honesty: layer resolution by byte range on this
Helix version may not behave as `layers_for_byte_range`'s source
suggests. Anyone reviving a layer-walking approach (a Path B-style
fallback) should re-verify it first.

## 7. Debugging

The `:todo-diagnostic` command was a development tool and was removed in
the final cleanup; its history lives in the repository (it reported tag
capture counts, the loader's language trace, and the injected-layer
resolution for the buffer). To debug detection on a new installation:

- Confirm the buffer's language injects `comment` (e.g. Rust `//`
  comments do; `///` doc comments inject `markdown-rustdoc`).
- Remember the colon rule: `// TODO:` is a structural tag, a colon-less
  `TODO` is not.
- `:tree-sitter-subtree` shows the parse tree at the cursor — place the
  cursor inside the comment to inspect the injected comment layer's
  nodes (`tag`, `name`, `text`).
- The loader contract (§1) is the first suspect when captures come back
  empty on a pipeline that otherwise runs: every traversed language
  must yield a query, not just `comment`.

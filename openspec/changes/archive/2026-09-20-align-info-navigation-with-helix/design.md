## Context

The current implementation in `navigation.scm` walks the root host-language tree, identifies comment node kinds, scans their text with a regex, compares line numbers, and delegates the final movement to `goto-line`. Helix itself uses Tree-sitter textobject ranges and byte-based strict comparisons for `]c` and `[c`.

Steel exposes two relevant paths:

- `query-document` with a language-dispatching `tsquery-loader`, which can traverse injected layers;
- `document->tree-byte-range`, which can retrieve the smallest injected tree for a known host-comment range without using the boxed query callback.

The implementation must keep the current commands silent and local to the active document while improving detection and motion semantics.

## Goals / Non-Goals

**Goals:**

- Validate the injected `comment` query pipeline before choosing the final detection path.
- Recognize structured `tag`/`name` nodes and return document byte ranges.
- Match Helix's strict forward/backward ordering, no-wrap behavior, counts, and directional selections.
- Preserve the pre-motion selection in the jumplist while avoiding register, search, and document mutations.
- Keep a structured injected-tree fallback available when the boxed callback path is unreliable.

**Non-Goals:**

- Dynamically read Helix's query files at runtime; the exposed Steel environment does not provide a stable filesystem query API for this purpose.
- Change Helix's native `]c` implementation or add new upstream Helix APIs.
- Add project-wide, cross-buffer, picker, or configurable navigation in this change.
- Add warning, error, or hint navigation unless the resulting implementation requires a reusable internal tag abstraction.

## Decisions

### 1. Validate `query-document` before refactoring navigation

The first implementation step will use a minimal query compiled for the `comment` grammar and a loader that returns it only when the requested language is `comment`. The query will capture the `name` node of supported `tag` nodes and use `#any-of?` for the info vocabulary.

This isolates the unknown boxed Steel behavior from navigation logic. The diagnostic must record whether the loader receives `comment`, whether captures are returned, and whether their byte ranges map directly to the document rope.

Alternative considered: immediately expanding the existing root tree walk. Rejected as the first step because it would preserve the main limitation under investigation and make a later query failure harder to diagnose.

### 2. Use the injected `comment` grammar as the source of structure

The preferred detector will query injected comment layers rather than scan arbitrary host-comment text. The query will capture both the tag node used for navigation and its name node used for filtering if both are needed by the final selection behavior.

The query source will be maintained in the plugin and will mirror Helix's current info vocabulary. It will not claim automatic synchronization with Helix's runtime query file because that file is not exposed as a plugin API.

If the query loader cannot reliably return a compiled query or captures, the fallback will first identify host comment ranges, retrieve each corresponding injected tree with `document->tree-byte-range`, and traverse `tag`/`name` nodes directly. The regex-over-comment-text path remains only as a last compatibility fallback if no injected tree is available.

Alternative considered: continuing to match `\\b(TODO|NOTE|INFO)\\b` against host comment text. Rejected as the primary path because it duplicates parsing, misses Helix's full vocabulary, and cannot distinguish structured tags from arbitrary comment text as precisely.

### 3. Order targets by document byte positions

All detected targets will be represented by start and end byte positions, converted to character positions only when constructing Helix `Range` values. Forward selection will require `start_byte > cursor_byte`; backward selection will require `end_byte < cursor_byte`.

Forward ties will prefer the earliest start and deterministic span ordering. Backward ties will prefer the latest end and deterministic span ordering, following `movement::goto_treesitter_object` as closely as the available Steel APIs allow.

Alternative considered: retaining line-based pairs. Rejected because it cannot distinguish multiple tags on one line and does not reproduce native Tree-sitter motion semantics.

### 4. Reproduce native selection orientation

For each active selection range, the detector will search from that range's cursor and apply the requested count repeatedly. The resulting target will be converted to a character-based `Range`:

- forward: anchor at target start, head at target end;
- backward: anchor at target end, head at target start.

The resulting selection will be committed through the exposed selection primitives. The implementation must preserve all selection ranges where a target exists and leave an individual range unchanged when it has no target.

### 5. Preserve the jumplist through the existing movement bridge

Steel exposes selection replacement but not the internal `push_jump` helper. The design will therefore use an existing jump-producing movement, such as `goto-line`, to record the pre-motion selection, then replace the temporary movement result with the exact Tree-sitter ranges.

This bridge must be verified with single and multiple selections. If it cannot preserve the required native behavior without unwanted cursor changes, the implementation will retain exact selections and document the jumplist limitation rather than mutate unrelated editor state.

## Risks / Trade-offs

- **Boxed query callback remains unreliable** -> Keep the minimal diagnostic separate from navigation and implement the injected-tree fallback before removing the working detector.
- **Helix changes its info vocabulary** -> Keep the vocabulary centralized and covered by tests; automatic runtime reuse is not available through the current Steel APIs.
- **Some languages do not inject `comment`** -> Treat missing syntax/injection as a silent no-op and retain host-comment fallback only where it is explicitly safe.
- **Injected node ranges may not map as expected** -> Validate byte positions against the document rope before using them and reject invalid ranges silently.
- **Selection and jumplist APIs do not expose native `push_jump` directly** -> Use the existing jump-producing command as a bridge and test that registers, search state, and multi-selections remain unchanged.
- **Native Helix textobject queries may be unavailable inside some injected layers** -> The plugin's tag detector will query the comment grammar directly instead of depending on `comment/textobjects.scm`.

## Migration Plan

1. Add and run the minimal query-pipeline diagnostic against representative languages.
2. Implement the preferred structured detector if the diagnostic succeeds; otherwise implement the injected-tree fallback.
3. Add byte-position ordering and exact directional selections behind the existing `todo-next` and `todo-prev` commands.
4. Verify no-match, count, multi-selection, jumplist, and no-parser behavior.
5. Keep the old detector available until the replacement passes the behavior checks, then remove obsolete helpers and update the README/spec references.

Rollback consists of restoring the previous detector and line-based movement helpers; command names and keybinding symbols remain unchanged.

## Open Questions

- Whether the exact `goto-line` bridge preserves a multi-selection jumplist entry in the same way as native motions must be answered by the implementation tests, not by changing the public contract.

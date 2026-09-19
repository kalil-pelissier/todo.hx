## Why

The current info-comment navigation works, but it only walks host-language comment nodes, compares line numbers, and moves to the first non-whitespace character. This differs from Helix's native Tree-sitter motions and prevents the plugin from using the structured `comment` injection that Helix already uses for tag highlighting.

The change should first validate Helix Steel's `query-document` pipeline for injected `comment` trees before refactoring navigation. If that pipeline remains unusable, the implementation will fall back to a structured injected-tree approach rather than relying only on a regex over host comments.

## What Changes

- Add a focused diagnostic path for querying `comment` injection layers through Steel's `query-document` and `tsquery-loader` APIs.
- Detect info tags from structured Tree-sitter `tag`/`name` nodes, using Helix's current info-tag vocabulary.
- Preserve the existing navigation commands while the query approach is validated, then replace detection only after the diagnostic succeeds.
- Align navigation ordering with Helix's byte-based strict forward/backward comparisons instead of line-only comparisons.
- Move toward native motion semantics: exact Tree-sitter ranges, count support, multi-selection handling, and jump-list preservation.
- Define a fallback based on `document->tree-byte-range` and injected `comment` trees if the boxed Steel query callback cannot reliably return compiled queries or captures.

## Capabilities

### New Capabilities

### Modified Capabilities

- `info-comment-navigation`: change info-tag detection and navigation semantics to use structured Tree-sitter positions and match Helix's native comment-motion behavior more closely.

## Impact

- Affects `navigation.scm` and its Steel Tree-sitter/editor dependencies.
- Uses Helix APIs exposed by `helix/treesitter.scm`, including `query-document`, `tsquery-loader`, `string->tsquery`, and selection/range primitives.
- May change the observable destination from a line's first non-whitespace character to an exact selected Tree-sitter range.
- No new external package dependency is expected.

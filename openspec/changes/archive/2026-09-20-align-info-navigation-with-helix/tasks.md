## 1. Validate Steel Tree-sitter Querying

- [x] 1.1 Add a minimal diagnostic for `query-document` that dispatches only the `comment` language and compiles a small `tag`/`name` query.
- [x] 1.2 Exercise the diagnostic on representative injected-comment languages and record loader language values, capture counts, and document byte ranges. _(Result on a Rust buffer: loader walk rust → rust-format-args-macro → rust → comment ×6 → markdown-rustdoc → markdown; raw=2+ info=1 on the TODO+FIXME control file. Root cause of the earlier count=0 found: `run_query` skips a layer's injections when the loader returns #f — the loader must return a query, even an empty pass-through, for every traversed language. The archived "boxed FFI" conclusion was wrong.)_
- [x] 1.3 Decide the detector path from the diagnostic result: query-based detection when captures are reliable, structured injected-tree traversal otherwise. _(Decision: Path A — query-document with an empty-query pass-through for the root language. Captures and `#any-of?` predicates both work on Helix 25.07.1.)_

## 2. Implement Structured Tag Detection

- [x] 2.1 Centralize the Helix info-tag vocabulary and represent each detected tag with document start and end byte positions.
- [x] 2.2 Implement the preferred `query-document` detector, including language dispatch, capture extraction, invalid-range handling, and silent no-parser behavior.
- [x] 2.3 Implement the `document->tree-byte-range` fallback that traverses injected `comment` nodes and identifies `tag`/`name` nodes without arbitrary text matching. _(Not required: the design's migration plan makes the fallback conditional on the diagnostic failing; Path A validated, so the fallback stays unimplemented.)_
- [x] 2.4 Remove or isolate obsolete regex-only detection once the selected structured detector passes the validation scenarios. _(The regex detector was removed outright in the Path A rewrite; no legacy code remains.)_

## 3. Match Helix Motion Semantics

- [x] 3.1 Replace line-based target ordering with strict byte-position comparisons and deterministic forward/backward tie-breaking.
- [x] 3.2 Apply counts by repeating target selection independently from each active selection range without wrapping.
- [x] 3.3 Construct directional character-based ranges so forward navigation has its head at the target end and backward navigation has its head at the target start.
- [x] 3.4 Commit exact target selections while preserving unaffected multi-selections and leaving selections unchanged when no target exists.
- [x] 3.5 Preserve the pre-motion selection in the jumplist using the available Steel movement/selection bridge, and verify jump-back behavior.

## 4. Verify and Document Behavior

- [x] 4.1 Test next/previous navigation, same-line multiple tags, strict boundaries, counts, no-wrap, no-parser, and no-match silence. _(User-validated: forward/backward ordering, no-wrap silent no-op, AUTODOC/FIXME skipped, .txt no-op.)_
- [x] 4.2 Test injected comments and tag variants across representative languages, including false substring matches such as `AUTODOC`. _(User-validated on Rust; the colon rule documented in ARCHITECTURE.md explains why a colon-less second TODO is highlighted but not navigable.)_
- [x] 4.3 Test register/search preservation, document immutability, exact selection ranges, multi-selection behavior, and jumplist behavior. _(User-validated: <C-o> jump-back, search register preserved, multi-cursor transforms per-range.)_
- [x] 4.4 Update the README to describe the actual Tree-sitter detection path, tag vocabulary, selection semantics, count support, and fallback limitations. _(Plus ARCHITECTURE.md with the end-to-end pipeline, the loader-contract root cause, and all problems/fixes.)_
- [x] 4.5 Remove temporary diagnostics and run OpenSpec validation plus the repository's available verification commands. _(Diagnostic and its helpers removed; the query is kept as a maintained copy with a provenance note per the review decision; the user's helix.scm provide list updated; paren-balance check passed; OpenSpec validation below.)_

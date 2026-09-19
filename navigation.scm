(require "helix/editor.scm")
(require (prefix-in helix.static. "helix/static.scm"))
(require (prefix-in helix. "helix/commands.scm"))
(require "helix/treesitter.scm")
(require-builtin helix/core/text as text.)

(provide todo-next todo-prev)

;; ── Info-tag vocabulary + query ──────────────────────────────────
;; One pattern: the whole `tag` node is the navigation target, gated
;; by an #any-of? predicate on its `name` child.
;;
;; PROVENANCE: the tag vocabulary mirrors the @info #any-of? list in
;; Helix's runtime/queries/comment/highlights.scm. That file cannot be
;; read at runtime (Steel plugins have no filesystem access, and the
;; runtime path is not stable across installations) and is not usable
;; verbatim (we capture the whole `tag` node for the selection range,
;; not the `name` node). When Helix updates its @info list, sync this
;; copy. See ARCHITECTURE.md §4 for the full rationale.

(define tag-query-src
  (string-append
    "((tag (name) @info.name) @info.tag"
    " (#any-of? @info.name"
    " \"INFO\" \"NOTE\" \"TODO\" \"TO-DO\" \"PERF\""
    " \"OPTIMIZE\" \"PERFORMANCE\" \"QUESTION\" \"ASK\""
    " \"REVIEW\" \"PR\" \"CR\"))"))

;; ── Utilities ────────────────────────────────────────────────────

(define (filter-map f lst)
  (if (null? lst)
      '()
      (let ([result (f (car lst))])
        (if result
            (cons result (filter-map f (cdr lst)))
            (filter-map f (cdr lst))))))

;; Sort by start-byte ascending, tie-break by end-byte ascending.
(define (sort-tag-pairs pairs)
  (sort pairs
    (lambda (a b)
      (or (< (car a) (car b))
          (and (= (car a) (car b))
               (< (cdr a) (cdr b)))))))

;; A detected tag: (start-byte . end-byte), or #f if invalid.
(define (node->pair node)
  (let ([s (tsnode-start-byte node)]
        [e (tsnode-end-byte node)])
    (and s e (> e s) (cons s e))))

;; ── Loader factory ───────────────────────────────────────────────
;; Helix's run_query skips a layer's injections when the loader
;; returns #f for that layer (extensions.rs: Ok(None) => continue).
;; The walk must therefore carry a query for every language it
;; traverses: the root language gets a pre-compiled empty query
;; (zero patterns) as a pass-through so the walk descends into the
;; injected "comment" layers.

(define (make-tag-loader compiled-info compiled-empty root-lang)
  (tsquery-loader
    (lambda (lang)
      (cond [(equal? lang "comment") compiled-info]
            [(equal? lang root-lang) compiled-empty]
            [else #f]))))

;; ── Tag detection ────────────────────────────────────────────────
;; Returns a sorted list of (start-byte . end-byte) pairs for all
;; info-level tags found in the document's injected comment layers.
;; Returns '() silently if no parser or no matches.

(define (scan-info-tags doc-id)
  (let* ([tree (document->tree doc-id)]
         [compiled (string->tsquery "comment" tag-query-src)])
    (if (or (not tree) (not compiled))
        '()
        (let* ([root-lang (tstree->language tree)]
               [compiled-empty (string->tsquery root-lang "")]
               [loader (make-tag-loader compiled compiled-empty root-lang)]
               [result (query-document loader doc-id)])
          (if (and result (TSMatch? result))
              (let ([tags (tsmatch-capture result "info.tag")])
                (if (not tags)
                    '()
                    (sort-tag-pairs (filter-map node->pair tags))))
              '())))))

;; ── Byte-position ordering ───────────────────────────────────────
;; Forward: smallest start-byte strictly > cursor-byte.
;; Tie-break: smallest start-byte, then smallest end-byte.
(define (find-first-ahead tags cursor-byte)
  (let loop ([tags tags] [best #f])
    (if (null? tags)
        best
        (let ([t (car tags)])
          (cond
            [(<= (car t) cursor-byte)
             (loop (cdr tags) best)]
            [(not best)
             (loop (cdr tags) t)]
            [(or (< (car t) (car best))
                 (and (= (car t) (car best))
                      (< (cdr t) (cdr best))))
             (loop (cdr tags) t)]
            [else
             (loop (cdr tags) best)])))))

;; Backward: largest end-byte strictly < cursor-byte.
;; Tie-break: largest end-byte, then largest start-byte.
(define (find-last-behind tags cursor-byte)
  (let loop ([tags tags] [best #f])
    (if (null? tags)
        best
        (let ([t (car tags)])
          (cond
            [(>= (cdr t) cursor-byte)
             (loop (cdr tags) best)]
            [(not best)
             (loop (cdr tags) t)]
            [(or (> (cdr t) (cdr best))
                 (and (= (cdr t) (cdr best))
                      (> (car t) (car best))))
             (loop (cdr tags) t)]
            [else
             (loop (cdr tags) best)])))))

;; ── Navigation ───────────────────────────────────────────────────
;; Each selection range transforms independently, like Helix's
;; goto_treesitter_object: ranges with a target become the exact
;; directional tag range, ranges without keep their value, and the
;; primary index is preserved. The jumplist bridge uses goto-line
;; (which pushes the pre-motion selection unconditionally) before
;; replacing the throwaway result with the exact tag selections.

;; The exact directional range for a tag, in char coordinates.
(define (target-range rope start-byte end-byte forward?)
  (let* ([start-char (text.rope-byte->char rope start-byte)]
         [end-char (text.rope-byte->char rope end-byte)])
    (if forward?
        (helix.static.range start-char end-char)
        (helix.static.range end-char start-char))))

;; Advance one range through `count` successive targets.
;; Returns the final range, or #f if no target was ever found.
(define (transform-range rope tags range count forward?)
  (let ([cursor-byte (text.rope-char->byte rope (helix.static.range-head range))])
    (let loop ([i 0] [pos cursor-byte] [best #f])
      (if (>= i count)
          best
          (let ([target (if forward?
                            (find-first-ahead tags pos)
                            (find-last-behind tags pos))])
            (if (not target)
                best
                (loop (+ i 1)
                      (if forward? (cdr target) (car target))
                      (target-range rope (car target) (cdr target) forward?))))))))

;; Transform every range; untouched ranges keep their current value.
;; Returns (new-ranges . any-found?).
(define (transform-ranges rope tags ranges count forward?)
  (let ([found (box #f)])
    (let loop ([rs ranges] [acc '()])
      (if (null? rs)
          (cons acc (unbox found))
          (let ([r (transform-range rope tags (car rs) count forward?)])
            (when r (set-box! found #t))
            (loop (cdr rs)
                  (append acc (list (if r r (car rs))))))))))

(define (nth lst i)
  (if (= i 0) (car lst) (nth (cdr lst) (- i 1))))

;; Commit a multi-range selection, restoring the primary index.
(define (commit-ranges new-ranges primary-idx)
  (helix.static.set-current-selection-object!
    (helix.static.range->selection (car new-ranges)))
  (let loop ([rest (cdr new-ranges)])
    (when (not (null? rest))
      (helix.static.push-range-to-selection! (car rest))
      (loop (cdr rest))))
  (let ([n (length (helix.static.selection->ranges
                     (helix.static.current-selection-object)))])
    (when (< primary-idx n)
      (helix.static.set-current-selection-primary-index! primary-idx))))

(define (navigate-selection doc-id tags forward?)
  (let* ([rope (editor->text doc-id)]
         [sel (helix.static.current-selection-object)]
         [ranges (helix.static.selection->ranges sel)]
         [primary-idx (helix.static.selection->primary-index sel)]
         [count (editor-count)]
         [results (transform-ranges rope tags ranges count forward?)]
         [new-ranges (car results)]
         [any-found? (cdr results)])
    (when any-found?
      ;; Jumplist bridge: goto-line pushes the pre-motion selection,
      ;; then we replace the throwaway movement with exact ranges.
      (let ([bridge-char (helix.static.range->from (nth new-ranges primary-idx))])
        (helix.goto-line (+ (text.rope-char->line rope bridge-char) 1)))
      (commit-ranges new-ranges primary-idx))))

;;@doc
;; Jump to the next info-level comment tag in the current buffer.
;; Selects the exact tag range; supports count prefix (e.g. 3]i).
(define (todo-next)
  (let* ([focus (editor-focus)]
         [doc-id (editor->doc-id focus)]
         [tags (scan-info-tags doc-id)])
    (when (not (null? tags))
      (navigate-selection doc-id tags #t))))

;;@doc
;; Jump to the previous info-level comment tag in the current buffer.
;; Selects the exact tag range; supports count prefix (e.g. 3[i).
(define (todo-prev)
  (let* ([focus (editor-focus)]
         [doc-id (editor->doc-id focus)]
         [tags (scan-info-tags doc-id)])
    (when (not (null? tags))
      (navigate-selection doc-id tags #f))))

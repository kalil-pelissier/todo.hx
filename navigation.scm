(require "helix/editor.scm")
(require (prefix-in helix.static. "helix/static.scm"))
(require (prefix-in helix. "helix/commands.scm"))
(require "helix/treesitter.scm")
(require-builtin helix/core/text as text.)

(provide todo-next todo-prev)

;; Word-boundary regex matching info-level tags.
;; Limited to TODO, NOTE, INFO for v1.
(define info-regex
  (text.rope-regex "\\b(TODO|NOTE|INFO)\\b"))

;; Check if a node kind is a comment type.
;; Different grammars use different names: line_comment, block_comment, comment.
(define (comment-kind? kind)
  (or (equal? kind "comment")
      (equal? kind "line_comment")
      (equal? kind "block_comment")
      (equal? kind "doc_comment")))

;; Recursively walk a tree-sitter node, collecting comment nodes.
;; Returns a list of TSNode.
(define (collect-comment-nodes node)
  (let ([kind (tsnode-kind node)]
        [children (tsnode-children node)])
    (if (comment-kind? kind)
        (cons node (collect-comment-nodes* children))
        (collect-comment-nodes* children))))

(define (collect-comment-nodes* nodes)
  (if (null? nodes)
      '()
      (append (collect-comment-nodes (car nodes))
              (collect-comment-nodes* (cdr nodes)))))

;; Extract the rope slice of a node from the rope.
(define (node-slice rope node)
  (let* ([start-byte (tsnode-start-byte node)]
         [end-byte (tsnode-end-byte node)]
         [start-char (text.rope-byte->char rope start-byte)]
         [end-char (text.rope-byte->char rope end-byte)])
    (text.rope->slice rope start-char end-char)))

;; Like map but filters out #f values.
(define (filter-map f lst)
  (if (null? lst)
      '()
      (let ([result (f (car lst))])
        (if result
            (cons result (filter-map f (cdr lst)))
            (filter-map f (cdr lst))))))

;; Sort pairs by line ascending, then byte offset ascending (task 4.3).
(define (sort-info-pairs pairs)
  (sort pairs
        (lambda (a b)
          (or (< (car a) (car b))
              (and (= (car a) (car b))
                   (< (cdr a) (cdr b)))))))

;; Scan the document for all comment lines containing info tags.
;; Walks the root tree-sitter tree to find comment nodes, then checks
;; their text for info-level tags using word-boundary regex.
;; Returns a sorted list of (line . byte) pairs, or '() if no parser / no match.
(define (scan-info-tag-lines doc-id)
  (let ([rope (editor->text doc-id)])
    (if (not rope)
        '()
        (let ([tree (document->tree doc-id)])
          (if (not tree)
              '()
              (let* ([root (tstree->root tree)]
                     [comments (collect-comment-nodes root)]
                     [pairs (filter-map
                              (lambda (node)
                                (let ([slice (node-slice rope node)])
                                  (and (text.rope-regex-match? info-regex slice)
                                       (let* ([byte (tsnode-start-byte node)]
                                              [char (text.rope-byte->char rope byte)]
                                              [line (text.rope-char->line rope char)])
                                         (cons line byte)))))
                              comments)])
                (sort-info-pairs pairs)))))))

;; Find the pair with the smallest line strictly greater than current-line.
;; Tie-break by smallest byte (matches movement.rs:597 semantics).
(define (find-first-ahead pairs current-line)
  (let loop ([pairs pairs] [best #f])
    (if (null? pairs)
        best
        (let ([p (car pairs)])
          (cond
            [(<= (car p) current-line)
             (loop (cdr pairs) best)]
            [(not best)
             (loop (cdr pairs) p)]
            [(or (< (car p) (car best))
                 (and (= (car p) (car best))
                      (< (cdr p) (cdr best))))
             (loop (cdr pairs) p)]
            [else
             (loop (cdr pairs) best)])))))

;; Find the pair with the largest line strictly less than current-line.
;; Tie-break by largest byte (matches movement.rs:600 semantics).
(define (find-last-behind pairs current-line)
  (let loop ([pairs pairs] [best #f])
    (if (null? pairs)
        best
        (let ([p (car pairs)])
          (cond
            [(>= (car p) current-line)
             (loop (cdr pairs) best)]
            [(not best)
             (loop (cdr pairs) p)]
            [(or (> (car p) (car best))
                 (and (= (car p) (car best))
                      (> (cdr p) (cdr best))))
             (loop (cdr pairs) p)]
            [else
             (loop (cdr pairs) best)])))))

;; Jump the cursor to the target line's first non-whitespace character.
;; goto-line expects 1-indexed, but rope-char->line returns 0-indexed.
(define (jump-to-line line)
  (helix.goto-line (+ line 1))
  (helix.static.goto_first_nonwhitespace))

;;@doc
;; Jump to the next info-level comment tag (TODO, NOTE, INFO) in the current buffer.
;; Mirrors Helix's goto_next_comment: strict comparison, no wrap, silent on no-match.
(define (todo-next)
  (let* ([focus (editor-focus)]
         [doc-id (editor->doc-id focus)]
         [pairs (scan-info-tag-lines doc-id)]
         [current-line (helix.static.get-current-line-number)])
    (let ([target (find-first-ahead pairs current-line)])
      (when target
        (jump-to-line (car target))))))

;;@doc
;; Jump to the previous info-level comment tag (TODO, NOTE, INFO) in the current buffer.
;; Mirrors Helix's goto_prev_comment: strict comparison, no wrap, silent on no-match.
(define (todo-prev)
  (let* ([focus (editor-focus)]
         [doc-id (editor->doc-id focus)]
         [pairs (scan-info-tag-lines doc-id)]
         [current-line (helix.static.get-current-line-number)])
    (let ([target (find-last-behind pairs current-line)])
      (when target
        (jump-to-line (car target))))))

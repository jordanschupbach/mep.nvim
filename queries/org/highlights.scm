;; A minimal, hand-written highlight query for the `org` tree-sitter
;; grammar (nvim-orgmode/tree-sitter-org). Deliberately not adapted from
;; nvim-orgmode's own query file, which relies on custom Lua predicates
;; (#org-is-headline-level?, #org-is-todo-keyword?, ...) that only exist
;; if that plugin registers them — this uses only predicates built into
;; Neovim's query engine (#any-of?), so it works standalone. That's also
;; why headlines get one heading color regardless of level, and only the
;; default TODO/DONE keywords are recognized here (mep.org's structural
;; features — cycling, parsing — still respect a custom
;; `todo_keywords` config; only this static query doesn't).

(headline stars: (stars) @markup.heading.1) @markup.heading

(headline item: (item . (expr) @keyword (#any-of? @keyword "TODO")))
(headline item: (item . (expr) @comment (#any-of? @comment "DONE")))

;; No dedicated priority node in this grammar (item/expr is a flat token
;; list, same reason TODO/DONE above are matched by literal text rather
;; than a keyword node) -- match any expr token that looks like a
;; priority cookie, unanchored to position. A title word that happens to
;; be exactly "[#A]"-shaped would also light up; an accepted tradeoff,
;; same class as the TODO/DONE simplification noted above.
(headline item: (item (expr) @constant (#match? @constant "^\\[#[A-Za-z0-9]\\]$")))

(headline tags: (tag_list) @tag)

(checkbox) @markup.list.checked
(bullet) @punctuation.special

(block) @markup.raw.block
(drawer) @comment
(property_drawer) @comment
(comment) @comment @spell

(timestamp) @markup.raw

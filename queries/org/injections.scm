;; Injects each `#+begin_src <lang> ... #+end_src` block's own tree-sitter
;; parser into its body, so a single org file highlights every language it
;; embeds with that language's own grammar (Neovim's built-in language-
;; injection mechanism does the rest once `vim.treesitter.start` is
;; running on the buffer — no extra activation step beyond what
;; mep.treesitter/mep.org already do for the outer `org` parser itself).
;;
;; `block`'s `parameter` field repeats once per header token (language,
;; then `:key value ...` pairs) — `.` anchors the captured parameter node
;; to just the *first* one, matching real org-babel's own header-argument
;; order. `#lua-match?` on `name` is a case-insensitive "SRC" check (real
;; org-mode accepts `#+begin_src`/`#+BEGIN_SRC`/any-case mix).
;;
;; Deliberately only built-in predicates/directives (`#eq?`, `#any-of?`,
;; `#lua-match?`, `#set!`) — same reason `highlights.scm`'s own header
;; comment gives for not leaning on a custom Lua predicate: this file is
;; discovered and run by Neovim's own query engine as soon as *any*
;; `org`-filetype buffer starts highlighting (mep.treesitter can do that
;; on its own, without mep.org.setup() ever running), so it can't depend
;; on mep.org having registered anything first — a missing custom
;; directive is a hard `error()` in Neovim's query engine, not a graceful
;; no-op (confirmed empirically), which would otherwise break *all*
;; highlighting for the buffer, base `org` highlighting included.
;;
;; Every pattern also sets `injection.include-children` — confirmed
;; empirically to be load-bearing, not defensive: Neovim's own injection
;; range computation (`get_node_ranges` in runtime/lua/vim/treesitter/
;; languagetree.lua) *excludes* an injected node's own named children by
;; default, on the assumption they're non-injectable structure (e.g. a
;; markdown fenced code block's own opaque text content has none, so the
;; distinction never matters there). `contents` here is the opposite: the
;; `org` grammar tokenizes a block's body into `expr`/`str` leaf nodes
;; that *are* the code itself, so excluding them leaves only the tiny
;; (usually zero-width) gaps between them — i.e. injecting almost nothing,
;; the language tree technically exists but covers no real text. Also
;; confirmed empirically: `(#set! injection.include-children)` with no
;; explicit value silently does nothing (metadata never gets set at all);
;; only the `(#set! key true)` form actually takes effect.
;;
;; The catch-all pattern below passes a block's language token straight
;; through as typed (correct already for the common case: `python`,
;; `lua`, `bash`, `rust`, ... typed lowercase, matching their tree-sitter
;; parser name exactly) — nothing-found just means no injection for that
;; capture, not an error, since `injection.language`'s resolver returns
;; nil for an unknown name. The `#set!`-based patterns above it handle
;; the divergent cases (`C++`/`cpp` share one parser; `sh`/`bash` share a
;; babel spelling but only `bash` has a grammar) and common alternate
;; capitalizations (`Python`, `RUBY`, ...) — a deliberately curated list
;; mirroring mep.org.babel.languages' own aliases (`bash=sh`, `js=
;; javascript`, `c++=cpp`), not an exhaustive one; a language spelled
;; some other way just falls through to the catch-all, same "graceful
;; miss" as everything else in this file.

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "c++" "C++" "cpp" "CPP" "Cpp")
  (#set! injection.language "cpp")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "C")
  (#set! injection.language "c")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "sh" "Sh" "SH" "bash" "Bash" "BASH" "shell" "Shell" "SHELL")
  (#set! injection.language "bash")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "js" "JS" "javascript" "JavaScript" "JAVASCRIPT")
  (#set! injection.language "javascript")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "ts" "TS" "typescript" "TypeScript" "TYPESCRIPT")
  (#set! injection.language "typescript")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Python" "PYTHON")
  (#set! injection.language "python")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Ruby" "RUBY")
  (#set! injection.language "ruby")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Perl" "PERL")
  (#set! injection.language "perl")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "R")
  (#set! injection.language "r")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "php" "PHP" "Php")
  ;; `php_only` (not `php`): confirmed empirically that org-babel PHP
  ;; body text, with no `<?php` tag of its own (real org-babel doesn't
  ;; require one either — see mep.org.babel.languages.php's own
  ;; wrap_php_tags, applied at *execution* time), parses under the
  ;; regular `php` grammar as one opaque `(program (text))` node — i.e.
  ;; "this looks like plain HTML", the same fallback a real `.php` file
  ;; with no opening tag gets — giving a highlight query nothing to ever
  ;; match. `php_only` is the *same* upstream repo's other grammar
  ;; variant, parsing bare PHP statements directly.
  (#set! injection.language "php_only")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Rust" "RUST")
  (#set! injection.language "rust")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Go" "GO" "golang" "Golang" "GOLANG")
  (#set! injection.language "go")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Java" "JAVA")
  (#set! injection.language "java")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Lua" "LUA")
  (#set! injection.language "lua")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "JSON" "Json")
  (#set! injection.language "json")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "yml" "YML" "YAML" "Yaml")
  (#set! injection.language "yaml")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "HTML" "Html")
  (#set! injection.language "html")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "CSS" "Css")
  (#set! injection.language "css")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "SQL" "Sql")
  (#set! injection.language "sql")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "TOML" "Toml")
  (#set! injection.language "toml")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Elixir" "ELIXIR")
  (#set! injection.language "elixir")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Julia" "JULIA")
  (#set! injection.language "julia")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Clojure" "CLOJURE")
  (#set! injection.language "clojure")
  (#set! injection.include-children true))

;; `c_sharp` (underscore), not `csharp`/`cs`/`c#` as typed — same
;; "typed spelling diverges from the parser's own name" reason `c++`
;; gets its own override above, mirroring mep.org.lang.treesitter_langs'
;; own (separately maintained, for the same "this file can't depend on
;; that module" reason given in this file's own header comment) `c_sharp`
;; normalization group.
(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "csharp" "CSharp" "CSHARP" "cs" "CS" "c#" "C#")
  (#set! injection.language "c_sharp")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Fortran" "FORTRAN")
  (#set! injection.language "fortran")
  (#set! injection.include-children true))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Scala" "SCALA")
  (#set! injection.language "scala")
  (#set! injection.include-children true))

;; Catch-all: pass the language token through exactly as typed — correct
;; already whenever it was typed lowercase and matching its own parser
;; name, which none of the overrides above already claimed.
(block
  name: (expr) @_name
  .
  parameter: (expr) @injection.language
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#set! injection.include-children true))

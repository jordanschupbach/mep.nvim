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
  (#set! injection.language "cpp"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "C")
  (#set! injection.language "c"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "sh" "Sh" "SH" "bash" "Bash" "BASH" "shell" "Shell" "SHELL")
  (#set! injection.language "bash"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "js" "JS" "javascript" "JavaScript" "JAVASCRIPT")
  (#set! injection.language "javascript"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "ts" "TS" "typescript" "TypeScript" "TYPESCRIPT")
  (#set! injection.language "typescript"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Python" "PYTHON")
  (#set! injection.language "python"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Ruby" "RUBY")
  (#set! injection.language "ruby"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Perl" "PERL")
  (#set! injection.language "perl"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "R")
  (#set! injection.language "r"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "PHP" "Php")
  (#set! injection.language "php"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Rust" "RUST")
  (#set! injection.language "rust"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Go" "GO" "golang" "Golang" "GOLANG")
  (#set! injection.language "go"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Java" "JAVA")
  (#set! injection.language "java"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "Lua" "LUA")
  (#set! injection.language "lua"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "JSON" "Json")
  (#set! injection.language "json"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "yml" "YML" "YAML" "Yaml")
  (#set! injection.language "yaml"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "HTML" "Html")
  (#set! injection.language "html"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "CSS" "Css")
  (#set! injection.language "css"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "SQL" "Sql")
  (#set! injection.language "sql"))

(block
  name: (expr) @_name
  .
  parameter: (expr) @_lang
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$")
  (#any-of? @_lang "TOML" "Toml")
  (#set! injection.language "toml"))

;; Catch-all: pass the language token through exactly as typed — correct
;; already whenever it was typed lowercase and matching its own parser
;; name, which none of the overrides above already claimed.
(block
  name: (expr) @_name
  .
  parameter: (expr) @injection.language
  contents: (contents) @injection.content
  (#lua-match? @_name "^[Ss][Rr][Cc]$"))

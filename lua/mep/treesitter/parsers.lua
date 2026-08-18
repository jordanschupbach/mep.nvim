--- Curated registry of common tree-sitter grammars: enough to cover most
--- everyday editing without trying to be the ~200+-language catalogue
--- nvim-treesitter maintains.
---
--- Each entry's `url`/`files`/`location`/`branch` was verified against
--- nvim-treesitter's own registry (lua/nvim-treesitter/parsers.lua) at
--- write time, not guessed from memory — several of these have moved
--- orgs over time (e.g. lua, markdown, yaml, toml, vim/vimdoc are *not*
--- under github.com/tree-sitter), and typescript/tsx/php/markdown build
--- from a `location` subdirectory of a shared repo rather than their own.
---
--- `files` are C source paths relative to the repo root (or `location`,
--- if set); `branch`, if set, is checked out instead of the repo's
--- default branch.
local M = {}

M.registry = {
  lua = {
    url = 'https://github.com/MunifTanjim/tree-sitter-lua',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  python = {
    url = 'https://github.com/tree-sitter/tree-sitter-python',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  javascript = {
    url = 'https://github.com/tree-sitter/tree-sitter-javascript',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  typescript = {
    url = 'https://github.com/tree-sitter/tree-sitter-typescript',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'typescript',
  },
  tsx = {
    url = 'https://github.com/tree-sitter/tree-sitter-typescript',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'tsx',
  },
  go = {
    url = 'https://github.com/tree-sitter/tree-sitter-go',
    files = { 'src/parser.c' },
  },
  rust = {
    url = 'https://github.com/tree-sitter/tree-sitter-rust',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  java = {
    url = 'https://github.com/tree-sitter/tree-sitter-java',
    files = { 'src/parser.c' },
  },
  ruby = {
    url = 'https://github.com/tree-sitter/tree-sitter-ruby',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  elixir = {
    url = 'https://github.com/elixir-lang/tree-sitter-elixir',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  julia = {
    url = 'https://github.com/tree-sitter/tree-sitter-julia',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  clojure = {
    url = 'https://github.com/sogaiu/tree-sitter-clojure',
    files = { 'src/parser.c' },
  },
  c = {
    url = 'https://github.com/tree-sitter/tree-sitter-c',
    files = { 'src/parser.c' },
  },
  cpp = {
    url = 'https://github.com/tree-sitter/tree-sitter-cpp',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  c_sharp = {
    url = 'https://github.com/tree-sitter/tree-sitter-c-sharp',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  fortran = {
    url = 'https://github.com/stadelmanma/tree-sitter-fortran',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  scala = {
    url = 'https://github.com/tree-sitter/tree-sitter-scala',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  bash = {
    url = 'https://github.com/tree-sitter/tree-sitter-bash',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  json = {
    url = 'https://github.com/tree-sitter/tree-sitter-json',
    files = { 'src/parser.c' },
  },
  yaml = {
    url = 'https://github.com/tree-sitter-grammars/tree-sitter-yaml',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  toml = {
    url = 'https://github.com/tree-sitter-grammars/tree-sitter-toml',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  html = {
    url = 'https://github.com/tree-sitter/tree-sitter-html',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  css = {
    url = 'https://github.com/tree-sitter/tree-sitter-css',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  markdown = {
    url = 'https://github.com/MDeiml/tree-sitter-markdown',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'tree-sitter-markdown',
  },
  markdown_inline = {
    url = 'https://github.com/MDeiml/tree-sitter-markdown',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'tree-sitter-markdown-inline',
  },
  sql = {
    url = 'https://github.com/derekstride/tree-sitter-sql',
    files = { 'src/parser.c', 'src/scanner.c' },
    branch = 'gh-pages',
  },
  php = {
    url = 'https://github.com/tree-sitter/tree-sitter-php',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'php',
  },
  -- Not a real standalone filetype (nothing ever sets `filetype=
  -- 'php_only'`) — the same repo's *other* grammar variant, parsing bare
  -- PHP statements directly with no `<?php` tag required. `php`'s own
  -- grammar requires one (a `.php` file with none is just static HTML —
  -- real PHP semantics), which real code embedded in something else
  -- (e.g. `mep.org.polyglot`'s own org-babel `#+begin_src php` blocks,
  -- via `queries/org/injections.scm`) doesn't have and shouldn't need to
  -- fake — confirmed empirically that unwrapped org-babel PHP body text
  -- parses as a single opaque `(program (text))` under the regular `php`
  -- grammar, giving a highlight query nothing to ever match.
  php_only = {
    url = 'https://github.com/tree-sitter/tree-sitter-php',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'php_only',
  },
  vim = {
    url = 'https://github.com/neovim/tree-sitter-vim',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  vimdoc = {
    url = 'https://github.com/neovim/tree-sitter-vimdoc',
    files = { 'src/parser.c' },
  },
  query = {
    url = 'https://github.com/nvim-treesitter/tree-sitter-query',
    files = { 'src/parser.c' },
  },
  dockerfile = {
    url = 'https://github.com/camdencheek/tree-sitter-dockerfile',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  org = {
    url = 'https://github.com/nvim-orgmode/tree-sitter-org',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  zig = {
    url = 'https://github.com/tree-sitter-grammars/tree-sitter-zig',
    files = { 'src/parser.c' },
  },
  nim = {
    url = 'https://github.com/alaviss/tree-sitter-nim',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  crystal = {
    url = 'https://github.com/crystal-lang-tools/tree-sitter-crystal',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  kotlin = {
    url = 'https://github.com/fwcd/tree-sitter-kotlin',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  haskell = {
    url = 'https://github.com/tree-sitter/tree-sitter-haskell',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  ocaml = {
    url = 'https://github.com/tree-sitter/tree-sitter-ocaml',
    files = { 'src/parser.c', 'src/scanner.c' },
    location = 'grammars/ocaml',
  },
  d = {
    url = 'https://github.com/gdamore/tree-sitter-d',
    files = { 'src/parser.c', 'src/scanner.c' },
  },
  -- Deliberately NOT a `perl` entry here — confirmed empirically this is
  -- worse than no entry at all, not just incomplete. nixpkgs' own prebuilt
  -- perl grammar (what `flake.nix`'s devShell puts on runtimepath) builds
  -- from `ganezdragon/tree-sitter-perl`, which ships a real `parser.c` but
  -- no `queries/` dir at all; the *only* upstream with a real perl
  -- `queries/highlights.scm` is the unrelated `tree-sitter-perl/
  -- tree-sitter-perl` org's grammar — a different project with a
  -- different node-type schema, not just a newer version of the same one.
  -- Pointing this entry at that second repo (so `M.install`'s
  -- `parser_ready` branch would clone it just for queries, alongside
  -- nixpkgs' *other* perl.so already on runtimepath) does resolve
  -- `M.has_queries('perl')` — but every query in the copied files then
  -- references node types (`(comment)` among them) that don't exist in
  -- the actual grammar the loaded parser was built from, throwing a real,
  -- visible "Invalid node type" tree-sitter query error the moment
  -- anything tries to highlight with it (confirmed the hard way against a
  -- real org buffer). Exactly the cross-upstream mixing this file's
  -- sibling entries (and `flake.nix`'s own header comment) already avoid
  -- on principle — `queries/org/injections.scm`'s own header comment
  -- documents the resulting "parser-only, no highlighting" tradeoff for
  -- `perl` (and `r`, in the same boat) until a from-scratch, same-source
  -- perl parser+queries pair exists somewhere.
}

--- Names of every parser in the curated registry, sorted.
function M.names()
  local names = {}
  for name in pairs(M.registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M

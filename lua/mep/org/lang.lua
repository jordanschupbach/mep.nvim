--- Normalizes an org-babel language token (whatever the user wrote after
--- `#+begin_src`, e.g. `python`, `C++`, `sh`) into the two separate names
--- that actually matter downstream: the Neovim `filetype` a mep.org.
--- polyglot shadow buffer needs for LSP attachment (`vim.lsp.enable`'s own
--- `FileType` autocmd matches on `filetypes` in a server's `vim.lsp.
--- Config`), and the tree-sitter parser name `mep.org.org` needs to
--- `mep.treesitter.install.install()` so `queries/org/injections.scm`'s
--- highlighting actually has a parser to inject — these occasionally
--- diverge from each other too (`c_sharp` the parser vs `cs` the
--- filetype).
---
--- Deliberately just a lookup table of the divergent cases, not an
--- exhaustive language list — same "curated slice" tradeoff
--- mep.treesitter.parsers/mep.lsp.servers already make; a language with no
--- entry here just passes its own lowercased spelling through unchanged,
--- which is correct for the common case (python, lua, ruby, rust, go,
--- java, php, json, yaml, ...).
local M = {}

--- raw babel token (lowercased) -> Neovim filetype, for every case where
--- they diverge. Mirrors mep.org.babel.languages' own aliases (`bash =
--- languages.sh`, `js = languages.javascript`, `c++ = languages.cpp`).
M.filetypes = {
  js = 'javascript',
  jsx = 'javascriptreact',
  ts = 'typescript',
  tsx = 'typescriptreact',
  -- Real org-babel's own shell language name is `sh` (`bash`/`shell` are
  -- common aliases) — Neovim's own filetype for all three is `sh`
  -- (`b:is_bash` distinguishes bash specifically), which is also what
  -- bash-language-server's `filetypes` list is keyed on.
  bash = 'sh',
  shell = 'sh',
  ['c++'] = 'cpp',
  cxx = 'cpp',
  c_sharp = 'cs',
  csharp = 'cs',
  ['c#'] = 'cs',
  golang = 'go',
  yml = 'yaml',
  emacs_lisp = 'lisp',
  elisp = 'lisp',
}

--- The Neovim filetype a src block's language should get, e.g. for a
--- mep.org.polyglot shadow buffer — lowercased passthrough of `raw` when
--- there's no divergent entry in `M.filetypes`.
function M.to_filetype(raw)
  if not raw or raw == '' then
    return nil
  end
  local key = raw:lower()
  return M.filetypes[key] or key
end

--- raw babel token (lowercased) -> tree-sitter parser name, for every case
--- where it diverges from the lowercased token itself. Kept in sync by
--- hand with `queries/org/injections.scm`'s own (separately hand-written,
--- since that file can't depend on this module being loaded — see its own
--- header comment) `#any-of?`/`#set!` normalization groups; used here only
--- to know which parser to `mep.treesitter.install.install()` for a given
--- block, not by the query file itself.
M.treesitter_langs = {
  ['c++'] = 'cpp',
  cxx = 'cpp',
  sh = 'bash',
  bash = 'bash',
  shell = 'bash',
  js = 'javascript',
  ts = 'typescript',
  tsx = 'tsx',
  golang = 'go',
  yml = 'yaml',
  c_sharp = 'c_sharp',
  csharp = 'c_sharp',
  ['c#'] = 'c_sharp',
  emacs_lisp = 'elisp',
  -- Not `php`: `queries/org/injections.scm` injects `php_only` for a
  -- `php`-language block (org-babel body text has no `<?php` tag, which
  -- the regular `php` grammar requires to parse as anything but opaque
  -- HTML text — see that query file's own comment on this pattern) — the
  -- *parser* this function names has to match, or `php_only` would never
  -- actually get installed for `mep.org.polyglot.ensure_language_parsers`
  -- to have anything to inject.
  php = 'php_only',
}

--- The tree-sitter parser name a src block's language should inject as —
--- lowercased passthrough of `raw` when there's no divergent entry in
--- `M.treesitter_langs`.
function M.to_treesitter_lang(raw)
  if not raw or raw == '' then
    return nil
  end
  local key = raw:lower()
  return M.treesitter_langs[key] or key
end

--- File extension (with leading dot, e.g. `.py`) to name a shadow buffer
--- with, so it resolves LSP `root_markers` sensibly. Reuses mep.org.babel's
--- own per-language `.extension` table (already correct for every
--- language it executes) where available, falling back to `.<filetype>`.
function M.to_extension(raw)
  if not raw or raw == '' then
    return '.txt'
  end
  local ok, babel = pcall(require, 'mep.org.babel')
  local def = ok and babel.languages[raw:lower()]
  if def and def.extension then
    return def.extension
  end
  return '.' .. M.to_filetype(raw)
end

return M

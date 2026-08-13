--- Turns on built-in treesitter features for a buffer, if (and only if) a
--- parser is actually available for its filetype — never attempts to
--- install anything itself; see install.lua for that.
local M = {}

--- Try to enable treesitter highlighting/folding for `bufnr`. `opts`:
--- `{ highlight = bool, fold = bool }` (both default true when opts is
--- omitted). Returns the resolved language name on success, or nil if
--- no parser is available for this buffer's filetype.
function M.enable_for_buffer(bufnr, opts)
  opts = opts or {}
  local ft = vim.bo[bufnr].filetype
  if ft == '' then
    return nil
  end

  local lang = vim.treesitter.language.get_lang(ft) or ft
  if not vim.treesitter.language.add(lang) then
    return nil
  end

  if opts.highlight ~= false then
    pcall(vim.treesitter.start, bufnr, lang)
  end

  if opts.fold then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.wo[win].foldmethod = 'expr'
      vim.wo[win].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    end
  end

  return lang
end

return M

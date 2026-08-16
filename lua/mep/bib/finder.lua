--- Locates `.bib` files for `bufnr`: first the current buffer's own
--- directory, and only if none are found there, the project root
--- (`mep.core.util.find_root`, the same `.git`-upward-search utility
--- `mep.picker`/`mep.project` build on) — not the buffer's *content*
--- (inline bibliography entries aren't a real BibTeX/org-cite concept,
--- so there's no sensible parse target for that literal reading of
--- "look in the buffer").
local util = require('mep.core.util')

local M = {}

--- Every `*.bib` path found for `bufnr` (defaulting to the current
--- buffer), per the two-step search order above — an empty list if
--- neither location has any.
function M.find_bib_files(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local dir = (path ~= '' and vim.fs.dirname(path)) or vim.fn.getcwd()

  local in_dir = vim.fn.glob(dir .. '/*.bib', false, true)
  if #in_dir > 0 then
    return in_dir
  end

  local root = util.find_root(dir)
  if root == dir then
    return {}
  end
  return vim.fn.glob(root .. '/*.bib', false, true)
end

return M

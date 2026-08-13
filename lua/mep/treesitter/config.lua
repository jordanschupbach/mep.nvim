local M = {}

M.defaults = {
  -- Start highlighting (vim.treesitter.start) for any buffer whose
  -- filetype has an available parser.
  highlight = true,
  -- Also set 'foldexpr' to vim.treesitter.foldexpr() the same way.
  -- Off by default since it changes fold behavior globally; folds start
  -- open ('foldenable' is untouched).
  fold = false,
  -- Parsers to make sure are installed, compiling any that are missing
  -- in the background on setup(): `true` for the whole curated list in
  -- mep.treesitter.parsers, a list of names for just those, or
  -- false/nil to never install anything (activate-only).
  ensure_installed = true,
  -- Where compiled parsers are installed. Defaults to a directory
  -- that's already on 'runtimepath' by default (stdpath('data')/site),
  -- so installed parsers are found with no further setup.
  install_dir = vim.fn.stdpath('data') .. '/site/parser',
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

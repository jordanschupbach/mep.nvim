local M = {}

M.defaults = {
  -- Display name for the scratch buffer (shown in `:ls`, the buffers
  -- picker, etc.) — `buftype=nofile` means it's never actually written
  -- to disk under this name, so collisions with a real file aren't a
  -- concern.
  name = 'scratch',
  -- Filetype set on the scratch buffer, e.g. 'markdown' for basic
  -- syntax highlighting while jotting notes. Empty by default (no
  -- filetype, plain text).
  filetype = '',
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

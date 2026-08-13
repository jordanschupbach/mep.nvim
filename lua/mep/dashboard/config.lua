local M = {}

M.defaults = {
  -- Show the dashboard automatically at startup, replacing Neovim's own
  -- intro screen, when started with no file arguments and an untouched
  -- empty buffer (the same conditions Neovim's own intro uses).
  auto_open = true,

  -- 'intro' (default): a constructed recreation of Neovim's own startup
  -- message (see mep.dashboard.content — it can't be captured live, so
  -- this is built in code). Or a function() -> {lines...}, or a plain
  -- list of strings.
  content = 'intro',
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

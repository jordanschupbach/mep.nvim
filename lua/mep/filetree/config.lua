local M = {}

M.defaults = {
  width = 30,
  -- nil = use core.util.find_root() (nearest ancestor with .git) at open time
  root = nil,
  show_hidden = false,
  keymaps = {
    open = { '<CR>', 'o' },
    expand = { 'l', '<Right>' },
    collapse = { 'h', '<Left>' },
    close = { 'q', '<Esc>' },
    refresh = { 'R' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

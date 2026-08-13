local M = {}

M.defaults = {
  -- Applied by setup() unless apply_on_setup = false.
  default = 'gruvbox-dark',
  apply_on_setup = true,
  keymaps = {
    -- Open the fuzzy theme picker (mep.picker-backed): live preview as
    -- you move the selection, Enter commits, Escape/<C-c> reverts to
    -- whatever was active before you opened it.
    picker = { '<leader>ut' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

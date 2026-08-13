local M = {}

M.defaults = {
  keymaps = {
    -- Open the URL under the cursor. Matches (and overrides — see
    -- mep.url.url's own header comment) Neovim's own built-in `gx`
    -- default.
    open = { 'gx' },
    -- List every URL in the current buffer via mep.picker and open
    -- whichever one you pick.
    pick = { 'gX' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

local M = {}

M.defaults = {
  -- mapleader/maplocalleader. Set to `false` to leave whatever the user
  -- has already configured untouched.
  leader = ' ',
  -- Line numbers ('number') and the sign column ('signcolumn'), on by
  -- default — set either to `false` to leave that option untouched
  -- instead (`mep.sanity.leader`'s own convention). `mep.dashboard`
  -- still turns both off for its own buffer regardless (`mep.dashboard.
  -- ui.prepare_window`), restoring whatever was here the moment a real
  -- buffer replaces it.
  number = true,
  signcolumn = true,
  -- Tab-management keymaps. `new` is a plain list of lhs strings, all
  -- bound to `:tabnew`. `select` is positional, not a plain list of
  -- equivalent bindings: `select[i]` jumps straight to tab `i` (`:tabnext
  -- i`) — Alt+1..9 by default, not `<C-Tab>`/`<C-S-Tab>`-style cycling,
  -- since terminals vary wildly in whether they even send a distinct
  -- code for Ctrl+Tab/Ctrl+Shift+Tab at all (most don't — confirmed the
  -- hard way, they're indistinguishable from plain Tab/`<C-i>` in a
  -- real terminal even though Neovim itself maps them just fine once
  -- fed the right bytes) where Alt+digit is universally reliable.
  -- Either list (or the whole `keymaps` table) set to `false`/`{}`
  -- leaves that action unbound.
  tabs = {
    keymaps = {
      new = { '<C-t>' },
      select = { '<A-1>', '<A-2>', '<A-3>', '<A-4>', '<A-5>', '<A-6>', '<A-7>', '<A-8>', '<A-9>' },
    },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

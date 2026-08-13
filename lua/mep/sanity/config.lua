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
  -- i`) — Mod1+1..9 by default (Alt on Linux/Windows, Option on macOS —
  -- see mep.config.defaults.mods), not `<C-Tab>`/`<C-S-Tab>`-style cycling,
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
      select = { '<Mod1-1>', '<Mod1-2>', '<Mod1-3>', '<Mod1-4>', '<Mod1-5>', '<Mod1-6>', '<Mod1-7>', '<Mod1-8>', '<Mod1-9>' },
    },
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied keymaps alike) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

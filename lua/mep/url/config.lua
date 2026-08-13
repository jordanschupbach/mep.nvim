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

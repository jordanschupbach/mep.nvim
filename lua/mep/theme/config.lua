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

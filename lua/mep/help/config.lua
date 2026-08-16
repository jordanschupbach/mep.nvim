local M = {}

M.defaults = {
  -- Extra/override library one-line descriptions, merged over
  -- `mep.help.descriptions.registry` (not replaced — the same
  -- override-over-curated pattern `mep.dap.config.defaults.adapters`
  -- uses), e.g. `{ my_lib = { desc = 'my own library', tag = 'my-lib' }
  -- }` so a project's own extra `mep.*`-style library shows up in the
  -- picker too.
  descriptions = {},
  keymaps = {
    -- Global trigger: opens the help picker.
    picker = { '<leader>?' },
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

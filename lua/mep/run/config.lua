local M = {}

M.defaults = {
  -- Extra/override filetype -> mep.org.babel language key mappings,
  -- merged over mep.run.languages.filetype_to_babel (not replaced —
  -- same override-over-curated pattern mep.dap.config.defaults.adapters
  -- uses).
  filetype_to_babel = {},
  -- `:terminal` split sizing — same shape/meaning as
  -- mep.project.config.defaults.terminal_height_ratio.
  terminal_height_ratio = 0.3,
  keymaps = {
    -- Run the current file.
    run = { '<leader>xr' },
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

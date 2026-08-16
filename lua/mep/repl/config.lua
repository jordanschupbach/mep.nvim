local M = {}

M.defaults = {
  -- 'filetype': one REPL is kept alive per filetype, shared across
  -- every buffer of that filetype. 'buffer': one REPL per source
  -- buffer instead.
  scope = 'filetype',
  -- Extra/override filetype -> REPL launch argv, merged over
  -- mep.repl.registry.commands (not replaced — same override-over-
  -- curated pattern mep.dap.config.defaults.adapters uses).
  commands = {},
  -- `:terminal` split sizing — same shape/meaning as
  -- mep.project.config.defaults.terminal_height_ratio.
  terminal_height_ratio = 0.3,
  keymaps = {
    send_line = { '<leader>sl' },
    -- Visual-mode only — send_selection needs an actual selection.
    send_selection = { '<leader>ss' },
    send_buffer = { '<leader>sb' },
    jump_to_repl = { '<leader>sr' },
    -- Bound inside the REPL terminal buffer itself, not globally (see
    -- mep.repl.repl's own header comment).
    jump_back = { '<leader>sc' },
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

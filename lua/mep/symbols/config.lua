local M = {}

M.defaults = {
  -- Fraction of the *current* window's width (not the whole tabpage —
  -- see mep.symbols.symbols.open's own header comment) the outline
  -- occupies when opened.
  width_ratio = 0.25,
  -- Sizing floor `width_ratio` won't shrink below, for a narrow current
  -- window.
  min_width = 20,
  -- Which side of the current window the outline splits off on:
  -- 'left'/'right'.
  position = 'right',
  keymaps = {
    -- Jump to the symbol under the cursor, in the buffer the outline
    -- was opened for.
    jump = { '<CR>' },
    close = { 'q', '<Esc>' },
    refresh = { 'R' },
  },
  -- Global trigger keymap, bound outside the panel itself (mep.picker's
  -- own `triggers` pattern) to toggle the outline for the current
  -- buffer. `false`/an empty list leaves it unbound.
  triggers = {
    toggle = { '<leader>ll' },
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

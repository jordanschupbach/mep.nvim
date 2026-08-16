local M = {}

M.defaults = {
  -- Charset labels are drawn from, in priority order (earlier characters
  -- assigned first). Home-row bias, the same default hop.nvim/flash.nvim
  -- ship. Single characters cover up to #labels targets; beyond that,
  -- two-character combinations (never mixed with single-character ones —
  -- see mep.hints.labels.assign) cover up to #labels^2.
  labels = 'asdfghjklqwertyuiopzxcvbnm',
  -- Global trigger keymaps, unbound by default (mep.picker's own
  -- `triggers` pattern): `char` starts character-search mode (prompts
  -- for a character, then labels every occurrence visible in the
  -- current window), `word` labels every visible word start
  -- immediately, no prompt.
  triggers = {
    char = {},
    word = {},
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied trigger keymaps alike) become the
-- concrete per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

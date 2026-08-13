local M = {}

M.defaults = {
  width = 30,
  -- nil = use core.util.find_root() (nearest ancestor with .git) at open time
  root = nil,
  show_hidden = false,
  keymaps = {
    open = { '<CR>', 'o' },
    expand = { 'l', '<Right>' },
    collapse = { 'h', '<Left>' },
    close = { 'q', '<Esc>' },
    refresh = { 'R' },
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

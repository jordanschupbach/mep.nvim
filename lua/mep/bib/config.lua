local M = {}

M.defaults = {
  keymaps = {
    -- Localleader (buffer-relative, not global `<leader>`, matching
    -- real org-ref's own `<localleader>` convention — this project
    -- doesn't set `vim.g.maplocalleader` itself, see mep.bib.bib's own
    -- header comment): browse/insert a citation reference at the
    -- cursor.
    insert = { '<localleader>ir' },
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

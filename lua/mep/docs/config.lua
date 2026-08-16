local M = {}

M.defaults = {
  -- Extra/override doc-lookup URL hints, merged over
  -- `mep.docs.templates.doc_hints` (not replaced — same
  -- `mep.dap.config.defaults.adapters`-over-`mep.dap.adapters.registry`
  -- pattern), e.g. `{ python = 'python~3.13' }` to pin a specific
  -- devdocs.io version slug.
  doc_hints = {},
  keymaps = {
    -- Insert a doc-comment skeleton for the function on/around the
    -- cursor.
    generate = { '<leader>ld' },
    -- Open external documentation for the word under the cursor.
    lookup = { '<leader>lD' },
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

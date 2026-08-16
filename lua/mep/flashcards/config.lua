local M = {}

M.defaults = {
  -- Which files a review session draws cards from — literal paths and/or
  -- glob patterns (e.g. `{'~/notes/*.org'}`), the exact same shape as
  -- `mep.org.agenda.config.defaults.agenda_files` (this library reuses
  -- `mep.org.agenda.files` itself to resolve them).
  drill_files = {},
  -- The tag (without colons) that marks a headline as a flashcard —
  -- `:drill:` by default, matching real org-drill's own convention.
  -- Inheritance-aware (`mep.org.tags.effective_tags`): a headline under
  -- a `:drill:`-tagged parent counts too, same as every other tag-aware
  -- operation in this project (`mep.org.agenda`'s own tag search
  -- included).
  tag = 'drill',
  keymaps = {
    -- Global trigger: starts a review session. Unlike a picker's own
    -- `triggers` (unbound by default), this is a real, sensible default
    -- keymap — same posture `mep.lsp`/`mep.dap`/`mep.docs` already take
    -- for their own primary action.
    review = { '<leader>fr' },
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

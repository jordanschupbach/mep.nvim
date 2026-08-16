local M = {}

M.defaults = {
  -- The centered buffer's own target width once zen mode adds side
  -- padding windows — real content narrower than this just leaves
  -- whitespace either side of it, the same as any fixed-width editor
  -- column. Ignored (no padding added) if the window is already
  -- narrower than this.
  width = 90,
  -- Individually toggle which pieces zen mode touches — same
  -- "everything independently disableable" convention mep.sanity uses.
  hide = {
    activitybar = true,
    filetree = true,
    symbols = true,
    gutter = true,
    chrome = true,
  },
  keymaps = {
    -- Global: toggle zen mode for the current window.
    toggle = { '<leader>zz' },
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

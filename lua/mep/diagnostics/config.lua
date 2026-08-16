local M = {}

M.defaults = {
  -- `false` leaves Neovim's native `vim.diagnostic` virtual_text/signs
  -- exactly as `mep.lsp` (or your own config) set them up — no circles,
  -- no forced `virtual_text = false` override.
  enable = true,
  -- The end-of-line marker placed once per diagnostic-bearing line
  -- (highest severity among that line's diagnostics wins the color —
  -- see `M.hl` below).
  circle = '●',
  -- Highlight group per `vim.diagnostic.severity` value, reusing the
  -- same `Diagnostic*` groups `mep.theme` already defines per palette
  -- (see `mep.theme.engine`) rather than introducing new ones.
  hl = {
    [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
    [vim.diagnostic.severity.WARN] = 'DiagnosticWarn',
    [vim.diagnostic.severity.INFO] = 'DiagnosticInfo',
    [vim.diagnostic.severity.HINT] = 'DiagnosticHint',
  },
  -- Border for `M.show_line_float`'s `vim.diagnostic.open_float` call.
  float = {
    border = 'rounded',
  },
  keymaps = {
    -- Global: expand the circle under/nearest the cursor's line into a
    -- floating window listing every diagnostic on it (Neovim's own
    -- `vim.diagnostic.open_float`, scoped to the line).
    show_line = { '<leader>ld' },
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

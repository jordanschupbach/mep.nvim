local M = {}

M.defaults = {
  -- Which bare-word keywords count as a "comment" this library scans
  -- for/highlights — matched as a whole word (`%f[%w]`/`%f[%W]` frontier
  -- boundaries in mep.todoscan.scan.match_line, `\b` in the `rg` pattern
  -- mep.todoscan.scan.scan builds), not restricted to any particular
  -- comment syntax (`//`, `#`, ...) — a bare-word match is enough.
  keywords = { 'TODO', 'FIXME', 'HACK', 'NOTE' },
  -- Recompute a buffer's own live signs/highlights this long after it
  -- stops changing — mep.git.gutter's own debounce, applied here.
  debounce_ms = 300,
  -- Whether mep.todoscan.highlight.enable() runs as part of setup() —
  -- the project-wide picker (M.picker()) works either way.
  highlight = true,
  -- Optional per-keyword sign-column glyph overrides (2 cells wide is
  -- the sign column's usual budget) — any keyword without an entry here
  -- (including the default four, and any custom keyword added beyond
  -- them) falls back to its own first two letters, uppercased.
  signs = {},
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (were any
-- ever added to this library's own config) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

local M = {}

M.defaults = {
  -- The org file (or glob pattern — see mep.org.agenda.files, which
  -- resolves this the same way it resolves mep.org.config.
  -- agenda_files) this panel lists headlines from. Unlike agenda_files
  -- (arbitrary multi-file, no sensible default), this panel's whole
  -- purpose is "the project's TODO.org", so it defaults to that
  -- conventional cwd-relative filename rather than an empty table —
  -- override with an absolute path (or your own glob) for anything
  -- else.
  file = 'TODO.org',
  panel = {
    position = 'right',
    width = 42,
    float = true,
    border = 'rounded',
    animate = true,
  },
  keymaps = {
    -- Global: open/close the panel.
    toggle = { '<leader>tt' },
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

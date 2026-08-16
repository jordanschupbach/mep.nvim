local M = {}

M.defaults = {
  -- Extra adapter entries, or overrides of a curated one (merged over
  -- `mep.dap.adapters.registry`, not replaced — same pattern
  -- `mep.lsp.config.defaults.servers` uses over its own curated
  -- registry). Same `{ cmd = {...}, filetypes = {...} }` shape.
  adapters = {},
  -- Sign-column markers, same `{ text, hl }` shape as
  -- `mep.git.config.defaults.signs` entries. `breakpoint` marks every
  -- toggled line; `stopped` marks the line execution is currently
  -- paused at (only one at a time — the current top stack frame).
  signs = {
    breakpoint = { text = '●', hl = 'MepDapBreakpoint' },
    stopped = { text = '▶', hl = 'MepDapStopped' },
  },
  -- Global keymaps (bound at `setup()` time, not per-buffer — debugging
  -- isn't filetype/LSP-attach-gated the way `mep.lsp.config.defaults.
  -- keymaps` is). `false`/an empty list leaves an action unbound.
  keymaps = {
    toggle_breakpoint = { '<leader>db' },
    continue = { '<leader>dc' },
    step_over = { '<leader>dn' },
    step_into = { '<leader>di' },
    step_out = { '<leader>do' },
    launch = { '<leader>dl' },
    terminate = { '<leader>dq' },
    toggle_sidebar = { '<leader>du' },
    toggle_repl = { '<leader>dr' },
    evaluate = { '<leader>de' },
  },
  -- `mep.dap.sidebar`'s own panel (call stack / scopes+variables /
  -- breakpoints) — same shape as `mep.git.config.defaults.sidebar`.
  sidebar = {
    position = 'right',
    width = 42,
    height = 15,
    border = 'rounded',
    animate = true,
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

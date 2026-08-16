--- Global keymaps for mep.dap (bound at `setup()` time, not per-buffer —
--- debugging isn't filetype/LSP-attach-gated the way `mep.lsp.keymaps`'s
--- own bindings are).
local M = {}

local function map(lhs_list, fn, desc)
  for _, lhs in ipairs(lhs_list or {}) do
    vim.keymap.set('n', lhs, fn, { desc = desc, silent = true })
  end
end

--- Bind `keymaps` (`mep.dap.config.defaults.keymaps`'s own shape).
--- `toggle_breakpoint` acts on the line under the cursor in the current
--- buffer at press time (not bound ahead of time to a specific buffer).
function M.bind(keymaps)
  local breakpoints = require('mep.dap.breakpoints')
  local session = require('mep.dap.session')
  local sidebar = require('mep.dap.sidebar')
  local repl = require('mep.dap.repl')

  map(keymaps.toggle_breakpoint, function()
    breakpoints.toggle(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1])
  end, 'mep.dap: toggle breakpoint')
  map(keymaps.continue, session.continue, 'mep.dap: continue')
  map(keymaps.step_over, session.step_over, 'mep.dap: step over')
  map(keymaps.step_into, session.step_into, 'mep.dap: step into')
  map(keymaps.step_out, session.step_out, 'mep.dap: step out')
  map(keymaps.launch, session.launch_interactive, 'mep.dap: launch')
  map(keymaps.terminate, session.terminate, 'mep.dap: terminate')
  map(keymaps.toggle_sidebar, sidebar.toggle_layout, 'mep.dap: toggle debug layout (sidebar + console)')
  map(keymaps.toggle_repl, repl.toggle, 'mep.dap: toggle debug console')
  map(keymaps.evaluate, repl.evaluate_interactive, 'mep.dap: evaluate expression')
end

return M

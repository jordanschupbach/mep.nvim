--- Aggregator for mep's window-manager library: a manual, mep-wm-style
--- layout (`mep.window.panes` — recursive `:vsplit`/`:split` panes,
--- each optionally holding several buffers as "tabs") plus a set of
--- on-demand automatic tiling layouts (`mep.window.auto` —
--- master-stack/vertical/horizontal/square/spiral, applied once when
--- you ask for them, never continuously enforced — see that module's
--- own header for why).
local config = require('mep.window.config')
local panes = require('mep.window.panes')
local auto = require('mep.window.auto')

local M = {}
M.panes = panes
M.auto = auto

local function bind_auto_keymaps()
  for _, name in ipairs(auto.names) do
    local lhs_list = config.options.auto.keymaps[name] or {}
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, function()
        auto.apply(name)
      end, { desc = 'mep.window: apply the ' .. name .. ' layout' })
    end
  end
end

--- Configure mep.window (see mep.window.config.defaults for `manual`
--- and `auto`) and, if `options.manual.enable` (the default), bind the
--- manual-layout keymaps and start syncing tab lists. Any populated
--- `auto.keymaps` entries are bound too — empty by default, since
--- there's no "correct" default chord for eight different layouts (see
--- mep.window.config.defaults.auto's own comment).
function M.setup(opts)
  local options = config.setup(opts)
  panes.disable()
  if options.manual.enable then
    panes.enable()
  end
  bind_auto_keymaps()
  return options
end

return M

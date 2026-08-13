--- Aggregator for mep's editor-chrome library: statusline/winbar/
--- tabline/statuscolumn, all built from the same widget shape (see
--- `mep.chrome.render`'s own header), plus an independent active-window
--- border (`mep.chrome.border`). `winbar`/`statuscolumn` are opt-in;
--- `statusline`/`tabline`/`border` are on by default — see `mep.chrome.
--- config.defaults`.
local config = require('mep.chrome.config')
local click = require('mep.chrome.click')
local hover = require('mep.chrome.hover')
local render = require('mep.chrome.render')
local mode = require('mep.chrome.mode')
local statusline = require('mep.chrome.statusline')
local winbar = require('mep.chrome.winbar')
local tabline = require('mep.chrome.tabline')
local statuscolumn = require('mep.chrome.statuscolumn')
local border = require('mep.chrome.border')

local M = {}
M.click = click
M.hover = hover
M.render = render
M.mode = mode
M.statusline = statusline
M.winbar = winbar
M.tabline = tabline
M.statuscolumn = statuscolumn
M.border = border

local function set_enabled(target, enable)
  if enable then
    target.enable()
  else
    target.disable()
  end
end

--- Configure mep.chrome (see `mep.chrome.config.defaults`) and
--- enable/disable each target to match. `mep.chrome.click`'s dispatch
--- function is always installed (cheap — a single global function; a
--- widget only becomes clickable if you give it `on_click`). Hover
--- tracking (`'mousemoveevent'`, real per-move overhead — see `:help
--- 'mousemoveevent'`) is only turned on when `statusline` or `winbar`
--- is enabled, the only two targets hover applies to.
function M.setup(opts)
  local options = config.setup(opts)

  click.enable()
  set_enabled(statusline, options.statusline.enable)
  set_enabled(winbar, options.winbar.enable)
  set_enabled(tabline, options.tabline.enable)
  set_enabled(statuscolumn, options.statuscolumn.enable)
  set_enabled(border, options.border.enable)

  if options.statusline.enable or options.winbar.enable then
    hover.enable()
  else
    hover.disable()
  end

  return options
end

function M._reset()
  statusline.disable()
  winbar.disable()
  tabline.disable()
  statuscolumn.disable()
  border.disable()
  hover._reset()
  click._reset()
end

return M

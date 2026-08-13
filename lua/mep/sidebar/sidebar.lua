--- Aggregator for mep's generic sidebar library: build your own
--- persistent side (or top/bottom) panel out of sections of clickable,
--- highlightable, hoverable widgets — `mep.activitybar`'s notification/
--- todo/test panels are all just `mep.sidebar` instances, not special
--- cases. See `mep.sidebar.render` for the section/widget shape and
--- `mep.sidebar.engine` (the `Sidebar` class returned by `new`) for the
--- open/close/toggle/resize/animate/collapse API.
local config = require('mep.sidebar.config')
local Sidebar = require('mep.sidebar.engine')
local render = require('mep.sidebar.render')

local M = {}
M.Sidebar = Sidebar
M.render = render
M.border_pad = Sidebar.border_pad

--- Configure global defaults every `new(opts)` instance falls back to
--- (per-instance `opts` still win) — see mep.sidebar.config.defaults.
function M.setup(opts)
  return config.setup(opts)
end

--- Build a new, closed Sidebar instance — see mep.sidebar.engine.Sidebar.new.
function M.new(opts)
  return Sidebar.new(opts)
end

return M

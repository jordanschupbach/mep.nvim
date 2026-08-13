--- Aggregator for mep's "sanity" library: a small set of sane Neovim
--- defaults, each independently configurable and individually
--- disableable (set its option to `false`). Building blocks live in
--- sibling files (leader.lua, ...); this file wires config to them. Like
--- every mep library, nothing here takes effect until `setup()` is
--- called.
local config = require('mep.sanity.config')
local leader = require('mep.sanity.leader')
local tabs = require('mep.sanity.tabs')
local gutter = require('mep.sanity.gutter')

local M = {}
M.leader = leader
M.tabs = tabs
M.gutter = gutter

--- Apply sanity defaults. `opts` overrides mep.sanity.config.defaults;
--- call with no args (or {}) to apply the defaults as-is.
function M.setup(opts)
  local options = config.setup(opts)
  leader.apply(options.leader)
  tabs.apply(options.tabs and options.tabs.keymaps)
  gutter.apply({ number = options.number, signcolumn = options.signcolumn })
  return options
end

return M

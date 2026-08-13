--- Aggregator for mep's git library: a gutter (sign-column hunk
--- markers, `]c`/`]g` / `[c`/`[g` navigation, stage/reset/preview-hunk
--- actions —
--- `mep.git.gutter`, diffing itself in `mep.git.diff`) plus a status
--- panel (`mep.git.sidebar`, built on `mep.sidebar`) showing changed
--- files and the current file's hunks, with commit/stage/unstage/
--- discard/refresh keymaps of its own. The panel opens two ways —
--- `mep.git.sidebar.toggle_dock()` (a floating panel flush against an
--- editor edge) or `.toggle_split()` (a real split, "pops up as a
--- split in the current buffer") — same content, opening one closes
--- the other.
local config = require('mep.git.config')
local diff = require('mep.git.diff')
local status = require('mep.git.status')
local gutter = require('mep.git.gutter')
local sidebar = require('mep.git.sidebar')

local M = {}
M.diff = diff
M.status = status
M.gutter = gutter
M.sidebar = sidebar

local function bind_global_keymaps()
  local km = config.options.keymaps
  for _, lhs in ipairs(km.toggle_sidebar) do
    vim.keymap.set('n', lhs, sidebar.toggle_split, { desc = 'mep.git: toggle git panel (split)' })
  end
  for _, lhs in ipairs(km.toggle_sidebar_dock) do
    vim.keymap.set('n', lhs, sidebar.toggle_dock, { desc = 'mep.git: toggle git panel (docked, floating)' })
  end
end

--- Configure mep.git (see mep.git.config.defaults for `enable`,
--- `debounce_ms`, `signs`, `keymaps`, `sidebar`) and, if `options.
--- enable` (the default), start attaching the gutter to git-tracked
--- buffers.
function M.setup(opts)
  local options = config.setup(opts)
  gutter.disable()
  if options.enable then
    gutter.enable()
  end
  bind_global_keymaps()
  return options
end

return M

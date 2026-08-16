--- Aggregator for mep's search-and-pick library. The `Picker` state machine
--- lives in engine.lua; this file wires it up to the three built-in
--- sources (files, grep, buffer_lines) and re-exports the public API, the
--- same way `mep.core.core` aggregates its building blocks.
local Picker = require('mep.picker.engine')
local config = require('mep.picker.config')
local keymaps = require('mep.picker.keymaps')

local M = {}
M.Picker = Picker

--- Configure the picker library: query debounce timings, the prompt
--- keymaps (select/close/next/prev), and trigger keymaps (e.g.
--- `triggers.buffer_search`) that open a picker from outside its own
--- prompt window. See mep.picker.config.defaults. Picker functions work
--- with sensible defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  keymaps.apply(options.triggers)
  return options
end

--- Build and open a picker from raw `Picker.new`-style opts. Use this to
--- assemble custom pickers from your own source (see
--- `lua/mep/picker/sources/*.lua` for examples).
function M.start(opts)
  Picker.new(opts):open()
end

--- Project file picker: fuzzy-find files under the project root (nearest
--- ancestor containing `.git`, or `opts.cwd` if given). Uses `rg --files`
--- when ripgrep is on PATH, falling back to a synchronous directory walk.
function M.find_files(opts)
  M.start(require('mep.picker.sources.files').picker_opts(opts))
end

--- Within-project search ("live grep"): greps the project root with `rg`
--- as you type. Requires ripgrep on PATH.
function M.live_grep(opts)
  M.start(require('mep.picker.sources.grep').picker_opts(opts))
end

--- Within-document search: fuzzy-find lines in the current (or given)
--- buffer.
function M.buffer_search(opts)
  M.start(require('mep.picker.sources.buffer_lines').picker_opts(opts))
end

--- Open-buffers picker: fuzzy-find among the current session's listed,
--- loaded buffers, most recently used first.
function M.buffers(opts)
  M.start(require('mep.picker.sources.buffers').picker_opts(opts))
end

return M

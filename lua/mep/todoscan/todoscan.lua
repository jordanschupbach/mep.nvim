--- Aggregator for mep's project-wide TODO/FIXME/HACK/NOTE comment
--- scanner — explicitly distinct from `mep.activitybar`'s own manual,
--- persisted todo list; no shared data store between the two, this
--- library only ever reads comments already in the code and never
--- writes anything. `M.picker()` (`:MepTodoScan`) scans the whole
--- project (`mep.todoscan.scan`: `rg` when available, a synchronous
--- walk+grep fallback otherwise); `mep.todoscan.highlight` keeps every
--- open buffer's own matches marked live (sign-column glyph plus a
--- highlight group per keyword), the same debounced attach/detach
--- lifecycle `mep.git.gutter` uses.
---
--- **Scope note**: the TODO this implements allows a `mep.picker`-
--- backed list "and/or" a `mep.sidebar` panel for results — only the
--- picker is implemented here. A persistent sidebar panel felt like a
--- second, much larger feature (its own live-refresh/expand-collapse
--- UI, `mep.activitybar`-style) rather than a small addition on top,
--- and the picker alone already covers "jump to the comment."
local config = require('mep.todoscan.config')
local scan = require('mep.todoscan.scan')
local picker = require('mep.todoscan.picker')
local highlight = require('mep.todoscan.highlight')

local M = {}
M.scan = scan
M.highlight = highlight

--- Open a `mep.picker`-backed list of every configured keyword found
--- across the project (`opts.cwd` to scan somewhere other than the
--- project root). `<CR>` jumps to the comment.
function M.picker(opts)
  require('mep.picker').start(picker.picker_opts(opts))
end

--- Configure mep.todoscan: `keywords`, `debounce_ms`, `highlight`
--- (whether live in-buffer signs/highlights are enabled), and `signs`
--- (see mep.todoscan.config.defaults). Works with sensible defaults
--- even if this is never called — only `highlight.enable()` itself
--- needs setup() to run.
function M.setup(opts)
  local options = config.setup(opts)
  if options.highlight then
    highlight.enable()
  end
  return options
end

return M

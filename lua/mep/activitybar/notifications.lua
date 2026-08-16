--- The notifications panel: a `mep.sidebar` instance sized/anchored the
--- same way as `.todo`/`.tests`/`.git` (this activity bar's own
--- position/panel_width/float/border/animate config, stacked next to
--- the icon column via `bar_edge_offset`), but its content, history,
--- and the `vim.notify` hook itself all come from the standalone `mep.
--- notify` library — `M.sidebar()` attaches this instance to it (`mep.
--- notify.attach`), the exact same "one shared data source, N attached
--- sidebar views" pattern `mep.activitybar.git` uses to attach to `mep.
--- git.sidebar`, so this panel and `mep.notify`'s own popups/standalone
--- panel/history all stay in sync rather than keeping a second copy of
--- any of it.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.activitybar.config')
local notify = require('mep.notify')

local M = {}

--- The bar's own content width — the display width of its widest
--- button icon (`mep.activitybar.activitybar`'s own `bar_content_width`,
--- duplicated here rather than required back, which would be circular:
--- that module already requires this one).
local function bar_content_width()
  local width = 1
  for _, b in ipairs(config.options.buttons) do
    width = math.max(width, vim.fn.strdisplaywidth(b.icon or ''))
  end
  return width
end

--- How far a panel needs to inset from the true screen edge to stack
--- next to the activity bar's own icon column, rather than overlapping
--- it — `mep.sidebar`'s own `edge_offset` (see its config.defaults),
--- fed the bar's total on-screen footprint (its content width plus
--- whatever its own border reserves).
local function bar_edge_offset()
  return bar_content_width() + sidebar_mod.border_pad(config.options.border)
end

local sidebar = nil

--- This panel's `mep.sidebar` instance, creating it (closed, and
--- attached to `mep.notify` via `M.attach`) the first time it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = notify.attach(sidebar_mod.new({
      title = 'Notifications',
      position = config.options.position,
      width = config.options.panel_width,
      float = config.options.float,
      border = config.options.border,
      edge_offset = bar_edge_offset(),
      animate = config.options.animate,
      sections = notify.sections(),
      on_open = function(sb)
        notify.bind_dismiss_keymaps(sb)
      end,
    }))
  end
  return sidebar
end

--- Open/close the notifications panel, refreshing its content first so
--- it's never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(notify.sections())
  sb:toggle()
end

--- Test/dev-only: drop the cached sidebar instance so a fresh
--- `sidebar()` starts clean. Does not touch `mep.notify`'s own state —
--- that module's own `_reset()` is still responsible for the entry
--- list/hook/popups this panel only ever reads.
function M._reset()
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
end

return M

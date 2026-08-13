--- The git panel: a `mep.sidebar` instance sized/anchored the same way
--- as `.notifications`/`.todo`/`.tests` (this activity bar's own
--- position/panel_width/float/border/animate config, stacked next to
--- the icon column via `bar_edge_offset`), but its content and action
--- keymaps (refresh/commit/stage/unstage/discard) come straight from
--- `mep.git.sidebar` — `M.attach` registers this instance alongside
--- `mep.git.sidebar`'s own `dock()`/`split()`, so all three stay in
--- sync (same `sections()`, redrawn together on a `mep.git.gutter.
--- on_change`) rather than being a separate copy of the same idea.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.activitybar.config')
local git_sidebar = require('mep.git.sidebar')

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
--- registered with `mep.git.sidebar` via `M.attach`) the first time
--- it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = git_sidebar.attach(sidebar_mod.new({
      title = 'Git',
      position = config.options.position,
      width = config.options.panel_width,
      float = config.options.float,
      border = config.options.border,
      edge_offset = bar_edge_offset(),
      animate = config.options.animate,
      -- Same reasoning as mep.git.sidebar's own dock()/split(): a
      -- status panel you glance at, not one that steals the cursor out
      -- of whatever you were editing.
      focus = false,
      sections = git_sidebar.sections(),
      on_open = function(sb)
        git_sidebar.bind_action_keymaps(sb)
        git_sidebar.refresh()
      end,
    }))
  end
  return sidebar
end

--- Open/close the git panel, refreshing its content first so it's
--- never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(git_sidebar.sections())
  sb:toggle()
end

--- Test/dev-only: drop the cached sidebar instance so a fresh
--- `sidebar()` starts clean. Does not touch `mep.git.sidebar`'s own
--- state — that module's own `_reset()` is still responsible for the
--- `mep.git.gutter.on_change` subscription this panel shares.
function M._reset()
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
end

return M

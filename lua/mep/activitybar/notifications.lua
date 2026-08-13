--- The notifications panel: a `mep.sidebar` instance fed by hooking
--- `vim.notify` itself, so anything anywhere (this project's own
--- libraries, your own config, another plugin) shows up without any
--- extra call — the same "introspect what's really there" approach
--- `mep.whichkey` takes for keymaps, applied to notifications instead.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.activitybar.config')

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

M.entries = {}
local next_id = 1
local orig_notify = nil
local sidebar = nil

local LEVEL_HL = {
  [vim.log.levels.ERROR] = 'DiagnosticError',
  [vim.log.levels.WARN] = 'DiagnosticWarn',
  [vim.log.levels.INFO] = 'DiagnosticInfo',
  [vim.log.levels.DEBUG] = 'DiagnosticHint',
  [vim.log.levels.TRACE] = 'DiagnosticHint',
}

local LEVEL_ICON = {
  [vim.log.levels.ERROR] = '✗',
  [vim.log.levels.WARN] = '⚠',
  [vim.log.levels.INFO] = 'ℹ',
  [vim.log.levels.DEBUG] = '·',
  [vim.log.levels.TRACE] = '·',
}

local function refresh()
  if sidebar then
    sidebar:set_sections(M.sections())
  end
end

--- Record `msg`/`level` as a new entry (newest first), trimming to
--- `config.options.notifications.max_entries`. Does *not* call through
--- to any real notification backend itself — `install()` is what wires
--- this into `vim.notify`; call this directly yourself if you want an
--- entry without a real notification alongside it.
function M.add(msg, level)
  table.insert(M.entries, 1, { id = next_id, text = tostring(msg), level = level or vim.log.levels.INFO, time = os.time() })
  next_id = next_id + 1
  local max = config.options.notifications.max_entries
  while #M.entries > max do
    table.remove(M.entries)
  end
  refresh()
end

--- Remove the entry with `id`.
function M.dismiss(id)
  for i, e in ipairs(M.entries) do
    if e.id == id then
      table.remove(M.entries, i)
      break
    end
  end
  refresh()
end

--- Remove every entry.
function M.clear()
  M.entries = {}
  refresh()
end

--- The `mep.sidebar` section list for the current `M.entries`: a
--- "Clear all" button (only when there's something to clear) followed
--- by one dismissible widget per entry, each colored by its log level
--- (Neovim's own `Diagnostic*` highlight groups, so this doesn't need
--- to define/document five new highlight groups of its own).
function M.sections()
  local widgets = {}
  if #M.entries > 0 then
    widgets[#widgets + 1] = { id = '__clear__', text = 'Clear all', icon = '🗑', on_click = function()
      M.clear()
    end }
  end
  for _, e in ipairs(M.entries) do
    widgets[#widgets + 1] = {
      id = tostring(e.id),
      text = e.text,
      icon = LEVEL_ICON[e.level] or LEVEL_ICON[vim.log.levels.INFO],
      hl = LEVEL_HL[e.level] or LEVEL_HL[vim.log.levels.INFO],
      tooltip = 'Click to dismiss',
      on_click = function()
        M.dismiss(e.id)
      end,
    }
  end
  if #widgets == 0 then
    widgets[1] = { id = '__empty__', text = 'No notifications' }
  end
  return { { id = 'notifications', title = 'Notifications', widgets = widgets } }
end

--- Hook `vim.notify` so every real notification also becomes an entry
--- here (idempotent — a second call is a no-op). The real notification
--- still goes through afterward; this only ever adds a side channel, it
--- never suppresses one.
function M.install()
  if orig_notify then
    return
  end
  orig_notify = vim.notify
  vim.notify = function(msg, level, opts)
    M.add(msg, level)
    return orig_notify(msg, level, opts)
  end
end

--- Undo `install()`.
function M.uninstall()
  if orig_notify then
    vim.notify = orig_notify
    orig_notify = nil
  end
end

--- This panel's `mep.sidebar` instance, creating it (closed) the first
--- time it's needed.
function M.sidebar()
  if not sidebar then
    sidebar = sidebar_mod.new({
      title = 'Notifications',
      position = config.options.position,
      width = config.options.panel_width,
      float = config.options.float,
      border = config.options.border,
      edge_offset = bar_edge_offset(),
      animate = config.options.animate,
      sections = M.sections(),
    })
  end
  return sidebar
end

--- Open/close the notifications panel, refreshing its content first so
--- it's never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(M.sections())
  sb:toggle()
end

--- Test/dev-only: drop the cached sidebar instance and hook state so a
--- fresh `sidebar()`/`install()` starts clean.
function M._reset()
  if sidebar then
    pcall(function()
      sidebar:close()
    end)
  end
  sidebar = nil
  M.entries = {}
  next_id = 1
  M.uninstall()
end

return M

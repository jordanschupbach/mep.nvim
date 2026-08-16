--- A standalone, nvim-notify/noice-style notification library: hook
--- `vim.notify` (`M.install`, called by `M.setup`) and
--- every real notification, from anywhere (this project's own
--- libraries, your own config, another plugin), becomes both a styled,
--- auto-dismissing popup toast (`mep.notify.popup`) and a permanent
--- entry in a scrollable history you can review and individually delete
--- in a `mep.sidebar`-based panel (`M.toggle`) — the same "introspect
--- what's really there" approach `mep.whichkey` takes for keymaps and
--- the original `mep.activitybar.notifications` took for notifications,
--- now promoted to its own library so it works with zero dependency on
--- `mep.activitybar` at all.
---
--- Unlike the old `mep.activitybar.notifications` hook, this one does
--- **not** forward to whatever `vim.notify` was before installing it —
--- the popup toast *is* the visible notification now (a real nvim-
--- notify/noice install replaces `vim.notify` outright for exactly this
--- reason: echoing the same message to `:messages` too would just be
--- noisy double-display). `M.uninstall` still restores the original
--- faithfully either way.
---
--- `mep.activitybar.notifications` is now a thin wrapper around this
--- module (`M.attach`, mirroring `mep.activitybar.git`'s own attachment
--- to `mep.git.sidebar`) — one shared entry list and hook, potentially
--- several `mep.sidebar` instances showing it at once, all refreshed
--- together.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.notify.config')
local popup = require('mep.notify.popup')

local M = {}
M.config = config
M.popup = popup

M.entries = {}
local next_id = 1
local orig_notify = nil
local instances = {}
local own_sidebar = nil

local LEVEL_HL = {
  [vim.log.levels.ERROR] = 'MepNotifyError',
  [vim.log.levels.WARN] = 'MepNotifyWarn',
  [vim.log.levels.INFO] = 'MepNotifyInfo',
  [vim.log.levels.DEBUG] = 'MepNotifyDebug',
  [vim.log.levels.TRACE] = 'MepNotifyDebug',
}

local function redraw()
  local sections = M.sections()
  for _, sb in ipairs(instances) do
    sb:set_sections(sections)
  end
end

--- Register an externally-constructed `mep.sidebar` instance so it
--- redraws alongside every other attached one whenever `M.entries`
--- changes — `mep.git.sidebar.attach`'s own pattern, applied here so
--- `mep.activitybar.notifications`'s own panel and `M.sidebar()`'s
--- standalone one can both show the same list live. Returns `sb`, so
--- callers can build-and-register inline.
function M.attach(sb)
  instances[#instances + 1] = sb
  return sb
end

--- Record `msg`/`level`/`opts.title` as a new history entry (newest
--- first), trimming to `config.options.max_entries`, and return it.
--- Does *not* show a popup itself — `M.notify` is what does both;
--- call this directly if you want a history entry with no popup.
function M.add(msg, level, opts)
  level = level or vim.log.levels.INFO
  table.insert(M.entries, 1, {
    id = next_id,
    text = tostring(msg),
    level = level,
    title = opts and opts.title,
    time = os.time(),
  })
  next_id = next_id + 1
  local max = config.options.max_entries
  while #M.entries > max do
    table.remove(M.entries)
  end
  redraw()
  return M.entries[1]
end

--- Remove the history entry with `id`.
function M.dismiss(id)
  for i, e in ipairs(M.entries) do
    if e.id == id then
      table.remove(M.entries, i)
      break
    end
  end
  redraw()
end

--- Remove every history entry.
function M.clear()
  M.entries = {}
  redraw()
end

--- The `mep.sidebar` section list for the current `M.entries`: a
--- "Clear all" button (only when there's something to clear) followed
--- by one dismissible widget per entry, colored/iconed by level from
--- `config.options.icons` and this module's own `MepNotify*` highlight
--- groups.
function M.sections()
  local icons = config.options.icons
  local widgets = {}
  if #M.entries > 0 then
    widgets[#widgets + 1] = {
      id = '__clear__',
      text = 'Clear all',
      icon = '🗑',
      on_click = function()
        M.clear()
      end,
    }
  end
  for _, e in ipairs(M.entries) do
    widgets[#widgets + 1] = {
      id = tostring(e.id),
      text = (e.title and e.title ~= '') and (e.title .. ': ' .. e.text) or e.text,
      icon = icons[e.level] or icons[vim.log.levels.INFO],
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

--- Read cursor-under-widget the same way `mep.git.sidebar`'s own
--- action keymaps do — only public `mep.sidebar` fields
--- (`sb.activatable`), no private engine methods.
local function widget_id_under_cursor(sb)
  local lnum = vim.api.nvim_win_get_cursor(sb.win)[1]
  local entry = sb.activatable[lnum]
  if not entry or entry.kind ~= 'widget' then
    return nil
  end
  return entry.widget_id
end

--- Bind `config.options.keymaps.dismiss`/`.clear` on `sb` (buffer-local)
--- — on top of `mep.sidebar`'s own default `<CR>`/click, which already
--- runs a widget's `on_click` (also a dismiss). Called from this
--- module's own `M.sidebar()`; `mep.activitybar.notifications` calls it
--- too, on its own differently-sized host sidebar.
function M.bind_dismiss_keymaps(sb)
  for _, lhs in ipairs(config.options.keymaps.dismiss) do
    vim.keymap.set('n', lhs, function()
      local id = widget_id_under_cursor(sb)
      if id and id ~= '__clear__' and id ~= '__empty__' then
        M.dismiss(tonumber(id))
      end
    end, { buffer = sb.buf, nowait = true, silent = true, desc = 'mep.notify: dismiss notification under cursor' })
  end
  for _, lhs in ipairs(config.options.keymaps.clear) do
    vim.keymap.set('n', lhs, M.clear, { buffer = sb.buf, nowait = true, silent = true, desc = 'mep.notify: clear all notifications' })
  end
end

--- Record `msg`/`level`/`opts` as a history entry *and* show it as a
--- popup toast — the actual `vim.notify` replacement (`M.install`
--- points `vim.notify` straight at this). Returns the new entry.
function M.notify(msg, level, opts)
  level = level or vim.log.levels.INFO
  local entry = M.add(msg, level, opts)
  popup.show(entry)
  return entry
end

--- Point `vim.notify` at `M.notify` (idempotent — a second call is a
--- no-op). See this module's own header comment for why, unlike the
--- old `mep.activitybar.notifications` hook, this does not also forward
--- to whatever `vim.notify` was before.
function M.install()
  if orig_notify then
    return
  end
  orig_notify = vim.notify
  vim.notify = M.notify
end

--- Undo `M.install`, restoring the original `vim.notify`.
function M.uninstall()
  if orig_notify then
    vim.notify = orig_notify
    orig_notify = nil
  end
end

--- This library's own standalone history panel, independent of `mep.
--- activitybar` — creating it (closed, attached via `M.attach`) the
--- first time it's needed.
function M.sidebar()
  if not own_sidebar then
    own_sidebar = M.attach(sidebar_mod.new({
      title = 'Notifications',
      position = config.options.panel.position,
      width = config.options.panel.width,
      float = config.options.panel.float,
      border = config.options.panel.border,
      animate = config.options.panel.animate,
      sections = M.sections(),
      on_open = function(sb)
        M.bind_dismiss_keymaps(sb)
      end,
    }))
  end
  return own_sidebar
end

--- Open/close the standalone history panel, refreshing its content
--- first so it's never stale from while it was closed.
function M.toggle()
  local sb = M.sidebar()
  sb:set_sections(M.sections())
  sb:toggle()
end

--- Configure `mep.notify` (see `mep.notify.config.defaults`) and
--- install the `vim.notify` hook.
function M.setup(opts)
  local options = config.setup(opts)
  M.install()
  return options
end

--- Test/dev-only: drop every attached sidebar instance (closing each
--- one, `mep.git.sidebar._reset`'s own pattern), every popup toast, and
--- every history entry, and uninstall the hook, so a fresh `setup()`/
--- `sidebar()` starts clean.
function M._reset()
  for _, sb in ipairs(instances) do
    pcall(function()
      sb:close()
    end)
  end
  instances = {}
  own_sidebar = nil
  M.entries = {}
  next_id = 1
  M.uninstall()
  popup._reset()
end

return M

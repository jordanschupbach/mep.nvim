--- Aggregator for mep's activity-bar library: a slim, persistent
--- icon-button column (a `mep.sidebar` instance with no header of its
--- own — `section.title = false`, "sidebars with just buttons") that
--- toggles one flyout panel per button, each *also* a `mep.sidebar`
--- instance that slides into view next to it. The flagship example of
--- what `mep.sidebar` is for, not a special case bolted onto it: every
--- piece here — the bar, `mep.activitybar.notifications`,
--- `.todo`, `.tests`, `.git` — is built entirely out of the same public
--- `mep.sidebar` API a user's own config would use (`.git`'s own panel
--- is additionally just a thin `mep.sidebar` wrapper around `mep.git.
--- sidebar`'s own content/keymaps, not a reimplementation of them).
local sidebar_mod = require('mep.sidebar')
local config = require('mep.activitybar.config')
local notifications = require('mep.activitybar.notifications')
local todo = require('mep.activitybar.todo')
local tests = require('mep.activitybar.tests')
local git = require('mep.activitybar.git')

local M = {}
M.notifications = notifications
M.todo = todo
M.tests = tests
M.git = git

--- Built-in panels, keyed by the `id` a `config.options.buttons` entry
--- names. Each must expose `toggle()` (open/close its own panel) —
--- `mep.activitybar.notifications`/`.todo`/`.tests`/`.git` all do; add
--- your own by extending this table with anything shaped the same way.
M.panels = {
  notifications = notifications,
  todo = todo,
  tests = tests,
  git = git,
}

local bar = nil
local autocmd_group = nil

--- The narrowest the button-bar column can be while still fitting every
--- configured button's icon in full: the display width (`vim.fn.
--- strdisplaywidth`, so a double-width emoji like the default 🔔 counts
--- as 2, not 1) of the widest one. Exactly wide enough, never a column
--- more — `mep.activitybar.notifications`/`.todo`/`.tests` each keep
--- their own identical copy of this function (see their own
--- `bar_edge_offset`) to size their `edge_offset` against, since
--- requiring this module back from any of them would be circular
--- (this module already requires all three).
local function bar_content_width()
  local width = 1
  for _, b in ipairs(config.options.buttons) do
    width = math.max(width, vim.fn.strdisplaywidth(config.icon_for(b)))
  end
  return width
end

local function build_bar_sections()
  local widgets = {}
  for _, b in ipairs(config.options.buttons) do
    widgets[#widgets + 1] = {
      id = b.id,
      text = '', -- icon-only — see mep.activitybar.config.defaults.buttons
      icon = config.icon_for(b),
      tooltip = b.label,
      on_click = function()
        M.toggle_panel(b.id)
      end,
    }
  end
  return { { id = 'buttons', title = false, widgets = widgets } }
end

--- The persistent button-bar `mep.sidebar` instance, creating it
--- (closed) the first time it's needed. Never animates open/close
--- (`animate = false`, regardless of `config.options.animate`) — a
--- real activity bar is meant to feel like a fixed, always-there
--- landmark, not something that slides around; only the *panels* it
--- toggles do. Floating (`config.options.float`, true by default) so
--- it neither disturbs nor gets disturbed by any other window. Never
--- takes focus either (`focus = false`) — opening it (including
--- automatically, on `VimEnter`, right alongside `mep.dashboard`'s own
--- auto-open) shouldn't pull the cursor away from whatever's actually
--- being edited/shown into a column of icons; click one (or `<C-w>w`
--- into it) when you actually want to use it.
function M.bar()
  if not bar then
    bar = sidebar_mod.new({
      position = config.options.position,
      width = bar_content_width(),
      float = config.options.float,
      border = config.options.border,
      animate = false,
      focus = false,
      sections = build_bar_sections(),
    })
  end
  return bar
end

--- Open/close the button bar itself.
function M.toggle_bar()
  M.bar():toggle()
end

--- Open/close the panel registered as `id` (`M.panels`).
function M.toggle_panel(id)
  local panel = M.panels[id]
  if not panel then
    vim.notify('mep.activitybar: unknown panel "' .. tostring(id) .. '"', vim.log.levels.WARN)
    return
  end
  panel.toggle()
end

--- Register the `VimEnter` autocmd that opens *just the bar* (never a
--- panel — real activity bars stay collapsed to their icons until you
--- click one) automatically on startup. Called by `setup()` unless
--- `auto_open = false`; exposed separately in case you want to turn it
--- on/off after the fact — `mep.dashboard.enable_auto_open`'s own
--- pattern, applied here.
function M.enable_auto_open()
  M.disable_auto_open()
  autocmd_group = vim.api.nvim_create_augroup('MepActivityBar', { clear = true })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = autocmd_group,
    callback = function()
      M.bar():open()
    end,
  })
end

function M.disable_auto_open()
  if autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
    autocmd_group = nil
  end
end

--- Configure mep.activitybar (see mep.activitybar.config.defaults),
--- start capturing `vim.notify` calls (`mep.notify.install`, idempotent
--- — `mep.activitybar.notifications` is just a `mep.sidebar` view onto
--- that library's own entries, not a second hook of its own), and,
--- unless `auto_open = false`, register the startup autocmd.
function M.setup(opts)
  local options = config.setup(opts)
  require('mep.notify').install()
  if options.auto_open then
    M.enable_auto_open()
  else
    M.disable_auto_open()
  end
  return options
end

--- Test/dev-only: drop every cached instance (the bar and all four
--- built-in panels) and stop listening for the startup autocmd, so a
--- fresh `bar()`/`setup()` starts clean.
function M._reset()
  M.disable_auto_open()
  if bar then
    pcall(function()
      bar:close()
    end)
  end
  bar = nil
  notifications._reset()
  todo._reset()
  tests._reset()
  git._reset()
end

return M

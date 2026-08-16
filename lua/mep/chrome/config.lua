local M = {}

--- The default `statusline` widget: a single box-drawing horizontal
--- rule spanning the window's full width, no text — just a plain line,
--- like a bottom border.
local function line_widget()
  return {
    text = function(ctx)
      return string.rep('─', vim.api.nvim_win_get_width(ctx.win))
    end,
  }
end

--- The default `tabline` `widgets_before`: the current mode
--- (`mep.chrome.mode.name()`), e.g. "Normal"/"Insert"/"Visual".
local function mode_widget()
  return {
    text = function()
      return ' ' .. require('mep.chrome.mode').name() .. ' '
    end,
    hl = 'ModeMsg',
  }
end

--- The default `tabline` `widgets_after`: a `+` to open a new tab
--- (`:tabnew`) and an `x` to close the current one (`:tabclose` —
--- silently a no-op on the last tab, same as `mep.chrome.tabline`'s own
--- per-tab circles never disappearing down to zero).
local function tab_add_widget()
  return {
    text = ' + ',
    on_click = function()
      vim.cmd('tabnew')
    end,
  }
end

local function tab_close_widget()
  return {
    text = ' x ',
    on_click = function()
      pcall(vim.cmd, 'tabclose')
    end,
  }
end

--- The default `tabline` `widgets_buttons`: right-aligned toggle
--- buttons for tests/notifications/git/filetree/symbols, one per
--- `mep.activitybar` flyout panel plus `mep.filetree`/`mep.symbols`'
--- own toggles. Each is a soft, optional dependency (`pcall`'d
--- `require`, resolved lazily at click time, not at config-definition
--- time) — clicking one without that library loaded/configured is a
--- harmless no-op, the same "everything independently optional"
--- convention `mep.zen` uses for its own soft deps.
local function toggle_button(icon_name, require_path)
  return {
    text = function()
      return ' ' .. (require('mep.icons').get_ui_icon(icon_name) or icon_name) .. ' '
    end,
    on_click = function()
      local ok, mod = pcall(require, require_path)
      if ok and mod.toggle then
        mod.toggle()
      end
    end,
  }
end

local function tabline_buttons()
  return {
    toggle_button('tests', 'mep.activitybar.tests'),
    toggle_button('notifications', 'mep.activitybar.notifications'),
    toggle_button('git', 'mep.activitybar.git'),
    toggle_button('filetree', 'mep.filetree'),
    toggle_button('symbols', 'mep.symbols'),
  }
end

M.defaults = {
  -- Each of winbar/statuscolumn is independently opt-in (`enable =
  -- false` by default — this project's own default editor chrome stays
  -- whatever Neovim/your own config already has it as, until you
  -- actually configure widgets for one of these and turn it on).
  -- `statusline`/`tabline` are the two exceptions, on by default (see
  -- each's own comment below). `widgets` is an ordered list of widget
  -- tables (see `mep.chrome.render`'s own header comment for the shape)
  -- — a plain string `'%='` inside it inserts a literal statusline
  -- alignment separator (left-aligned widgets before it, right-aligned
  -- after).
  statusline = {
    enable = true,
    widgets = { line_widget() },
  },
  winbar = {
    enable = false,
    widgets = {},
  },
  -- On by default, like `statusline` (see its own comment above) — a
  -- mode indicator, one clickable circle per tab (filled = current,
  -- hollow = not — mep.chrome.tabline's own click-to-switch, always on,
  -- not itself a widget you configure away, only bookend), then `+`/`x`
  -- to open/close a tab.
  tabline = {
    enable = true,
    -- Extra widgets rendered before/after the (always-on) circle tab
    -- list, plus a right-aligned row of panel-toggle buttons (`%=`
    -- pushes them flush against the tabline's right edge).
    widgets_before = { mode_widget() },
    widgets_after = { tab_add_widget(), tab_close_widget() },
    widgets_buttons = tabline_buttons(),
  },
  statuscolumn = {
    enable = false,
    -- Numbers/signs/folds are Neovim's own recommended statuscolumn
    -- building blocks (`:help 'statuscolumn'`'s own example) —
    -- individually toggleable; `widgets` are extra per-line segments
    -- rendered after them.
    signs = true,
    numbers = true,
    folds = true,
    widgets = {},
  },

  -- Highlights the currently active window's border — see `mep.chrome.
  -- border`'s own header comment for exactly how each of the 4 sides is
  -- achieved (all native window-local options, no floating overlay).
  -- Genuinely useful on its own even with every target above left off:
  -- `sides` alone still recolors the real 'WinSeparator' between panes.
  border = {
    enable = true,
    -- Which sides to actually recolor when a window becomes active.
    -- `top`/`bottom` only take effect for a window that already has
    -- `winbar`/a real per-window `statusline` shown (there's nothing
    -- there to recolor otherwise) — set `winbar.enable = true` (even
    -- with no widgets — a blank winbar is still a real top edge) for
    -- `top` to have anything to work with.
    sides = { left = true, right = true, top = true, bottom = true },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

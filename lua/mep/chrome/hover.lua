--- Hover tracking for mep.chrome widgets (statusline/winbar only —
--- tabline's tab labels use Neovim's own native click regions, and
--- statuscolumn is evaluated per screen *line*, not a fixed on-screen
--- rectangle, so "hover" isn't a coherent concept there).
---
--- Neovim's `%@` click mechanism resolves "which item was clicked"
--- itself, internally, at click time — there's no equivalent for an
--- arbitrary `<MouseMove>` position, so this module tracks it by hand:
--- `mep.chrome.render.render()` already returns each widget's on-screen
--- column range (see that module's header), and `.statusline`/`.winbar`
--- feed those ranges in here via `M.set_ranges(target, win, ranges)`
--- after every redraw. A `<MouseMove>` handler (enabled only when
--- `'mousemoveevent'` is on — see `M.enable`) reads the raw mouse
--- position via `getmousepos()`, classifies which row it's over
--- (winbar / statusline / neither, from the window's own height and
--- `'winbar'` option — there's no direct API for this, but it's a
--- fixed offset once you know whether the window has a winbar) and
--- looks up the matching range.
---
--- Column ranges are only reliable up to and including the first
--- `'%='` in a widget list (see mep.chrome.render) — widgets placed
--- after a *second* `'%='` won't receive on_hover/on_leave.
local M = {}

local ranges_by_target = { statusline = {}, winbar = {} }
local current -- { win, target, widget }
local tooltip_win, tooltip_buf

--- Called by mep.chrome.statusline/.winbar after each redraw of a
--- given window's bar.
function M.set_ranges(target, win, ranges)
  ranges_by_target[target][win] = ranges
end

function M.clear_ranges(target, win)
  ranges_by_target[target][win] = nil
end

local function classify_row(win, winrow)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local has_winbar = vim.api.nvim_get_option_value('winbar', { win = win }) ~= ''
  local content_h = vim.api.nvim_win_get_height(win)
  local content_top = has_winbar and 2 or 1
  local content_bottom = content_top + content_h - 1
  if has_winbar and winrow == 1 then
    return 'winbar'
  elseif winrow == content_bottom + 1 then
    return 'statusline'
  end
  return nil
end

local function find_widget(target, win, col)
  local ranges = ranges_by_target[target][win]
  if not ranges then
    return nil
  end
  for _, r in ipairs(ranges) do
    if col >= r.start_col and col < r.end_col then
      return r.widget
    end
  end
  return nil
end

local function build_ctx(win)
  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
  return {
    win = win,
    bufnr = ok and bufnr or vim.api.nvim_get_current_buf(),
    active = win == vim.api.nvim_get_current_win(),
  }
end

local function on_move()
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  local widget

  if win and win ~= 0 and vim.api.nvim_win_is_valid(win) then
    local target = classify_row(win, pos.winrow)
    if target then
      widget = find_widget(target, win, pos.wincol - 1)
    end
  end

  if current and current.widget ~= widget then
    if current.widget.on_leave then
      current.widget.on_leave(build_ctx(current.win))
    end
    current = nil
  end

  if widget and not current then
    current = { win = win, widget = widget }
    if widget.on_hover then
      widget.on_hover(build_ctx(win))
    end
  end

  vim.cmd('redrawstatus')
end

--- Convenience for widgets' own on_hover: pops a small floating
--- tooltip near the mouse. `text` is a string or a list of lines.
function M.show_tooltip(text)
  M.hide_tooltip()
  local lines = type(text) == 'table' and text or { text }
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local pos = vim.fn.getmousepos()
  tooltip_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tooltip_buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(tooltip_buf, 0, -1, false, lines)
  tooltip_win = vim.api.nvim_open_win(tooltip_buf, false, {
    relative = 'editor',
    row = math.max(pos.screenrow - #lines - 1, 0),
    col = math.max(pos.screencol - 1, 0),
    width = width,
    height = #lines,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    noautocmd = true,
  })
end

function M.hide_tooltip()
  if tooltip_win and vim.api.nvim_win_is_valid(tooltip_win) then
    vim.api.nvim_win_close(tooltip_win, true)
  end
  tooltip_win = nil
  tooltip_buf = nil
end

local enabled = false
local saved_mousemoveevent

function M.enable()
  if enabled then
    return
  end
  enabled = true
  saved_mousemoveevent = vim.o.mousemoveevent
  vim.o.mousemoveevent = true
  vim.keymap.set({ 'n', 'i', 'v', 'x' }, '<MouseMove>', on_move, { desc = 'mep.chrome: hover dispatch' })
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  for _, mode in ipairs({ 'n', 'i', 'v', 'x' }) do
    pcall(vim.keymap.del, mode, '<MouseMove>')
  end
  vim.o.mousemoveevent = saved_mousemoveevent
  current = nil
  M.hide_tooltip()
end

function M._reset()
  ranges_by_target = { statusline = {}, winbar = {} }
  current = nil
  M.hide_tooltip()
  if enabled then
    M.disable()
  end
end

return M

--- Shared statusline-format renderer used by mep.chrome.statusline,
--- .winbar, .tabline and .statuscolumn. A "widget" is a plain table:
---
---   { id, text, hl, on_click, on_hover, on_leave }
---
--- `text` is a string or `function(ctx) -> string`; `hl` is a
--- highlight group name or `function(ctx) -> string|nil`. `ctx` is
--- `{ win, bufnr, active }` — the window/buffer the bar is currently
--- being rendered for (for on_click/on_hover, the window actually
--- under the mouse instead). The literal string `'%='` may appear
--- anywhere in the widget list in place of a widget table — it
--- becomes a real statusline alignment separator (widgets before it
--- left-aligned, widgets after it right-aligned). Only the FIRST
--- `'%='` participates in the column-range tracking below; widgets
--- after a second one still render correctly but won't receive
--- on_hover/on_leave (see mep.chrome.hover's own header for why this
--- is an acceptable, documented limitation).
---
--- M.render(widgets, ctx) returns the rendered format-string fragment
--- plus a `ranges` list of `{ widget, start_col, end_col }` (0-based
--- screen columns, end exclusive, relative to the bar's own left
--- edge) — mep.chrome.hover uses this to resolve "which widget is the
--- mouse over" from a raw getmousepos() column.
local click = require('mep.chrome.click')

local M = {}

local function resolve(value, ctx)
  if type(value) == 'function' then
    return value(ctx)
  end
  return value
end

local function escape(text)
  return (text or ''):gsub('%%', '%%%%')
end

local function render_widget(widget, ctx)
  local raw = resolve(widget.text, ctx) or ''
  local hl = resolve(widget.hl, ctx)
  local body = escape(raw)
  if hl then
    body = '%#' .. hl .. '#' .. body .. '%#MepChromeNormal#'
  end
  if widget.on_click then
    local id = click.register(widget)
    body = '%' .. id .. '@v:lua.MepChromeClickDispatch@' .. body .. '%X'
  end
  return body, vim.fn.strdisplaywidth(raw)
end

--- ctx: `{ win = winid, bufnr = bufnr, active = bool }` (or `{ win,
--- bufnr, lnum }` for mep.chrome.statuscolumn's per-line evaluation).
function M.render(widgets, ctx)
  local parts = {}
  local ranges = {}
  local seen_align = false
  local win_width = (ctx.win and vim.api.nvim_win_is_valid(ctx.win)) and vim.api.nvim_win_get_width(ctx.win) or 0

  local left_col = 0
  local right_widgets = {}

  for _, widget in ipairs(widgets) do
    if widget == '%=' then
      parts[#parts + 1] = '%='
      seen_align = true
    elseif not seen_align then
      local body, width = render_widget(widget, ctx)
      parts[#parts + 1] = body
      ranges[#ranges + 1] = { widget = widget, start_col = left_col, end_col = left_col + width }
      left_col = left_col + width
    else
      local body, width = render_widget(widget, ctx)
      parts[#parts + 1] = body
      right_widgets[#right_widgets + 1] = { widget = widget, width = width }
    end
  end

  if #right_widgets > 0 then
    local total = 0
    for _, rw in ipairs(right_widgets) do
      total = total + rw.width
    end
    local col = win_width - total
    for _, rw in ipairs(right_widgets) do
      ranges[#ranges + 1] = { widget = rw.widget, start_col = col, end_col = col + rw.width }
      col = col + rw.width
    end
  end

  return table.concat(parts), ranges
end

return M

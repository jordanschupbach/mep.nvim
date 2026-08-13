--- mep.chrome's `'tabline'` target: `widgets_before` (default: a mode
--- indicator, `mep.chrome.mode`), then one clickable circle per
--- tabpage (filled = current, hollow = not — clicking one switches to
--- it), then `widgets_after` (default: `+`/`x` to open/close a tab).
--- The circles go through the same `mep.chrome.click` widget dispatch
--- statusline/winbar use (`%N@v:lua.MepChromeClickDispatch@...%X`, see
--- `mep.chrome.render`'s own header) rather than Neovim's native
--- `%NT...%X` tab-click grammar — unlike a filename label, "which tab
--- is this" isn't visible in a circle's own text, so a per-tab widget
--- table (closing over its own tab index) is what makes each circle's
--- own click resolvable at all, and it's what lets `+`/`x` sit in the
--- same bar as plain callbacks too.
local config = require('mep.chrome.config')
local render = require('mep.chrome.render')

local M = {}

local function current_ctx()
  return {
    win = vim.api.nvim_get_current_win(),
    bufnr = vim.api.nvim_get_current_buf(),
    active = true,
  }
end

-- tab index -> its circle widget table, reused across renders rather
-- than rebuilt every `eval()` call: `mep.chrome.click.register` stamps
-- a click id onto a widget the first time it's seen, keyed by table
-- identity — a fresh table per redraw would mean a fresh (leaked)
-- registry entry every redraw too. Each widget's `text`/`hl`/`on_click`
-- close over their own fixed index and re-check current state (`vim.fn.
-- tabpagenr()`) at render/click time, so the *same* table stays correct
-- as tabs open/close/reorder around it.
local circle_widgets = {}

local function circle_widget(i)
  local widget = circle_widgets[i]
  if not widget then
    widget = {
      text = function()
        return (i == vim.fn.tabpagenr()) and ' ● ' or ' ○ '
      end,
      hl = function()
        return (i == vim.fn.tabpagenr()) and 'TabLineSel' or 'TabLine'
      end,
      on_click = function()
        vim.cmd('tabnext ' .. i)
      end,
    }
    circle_widgets[i] = widget
  end
  return widget
end

function M.eval()
  local cfg = config.options.tabline
  local ctx = current_ctx()
  local parts = {}

  if #cfg.widgets_before > 0 then
    parts[#parts + 1] = (render.render(cfg.widgets_before, ctx))
  end

  local circles = {}
  for i = 1, vim.fn.tabpagenr('$') do
    circles[#circles + 1] = circle_widget(i)
  end
  parts[#parts + 1] = (render.render(circles, ctx))

  if #cfg.widgets_after > 0 then
    parts[#parts + 1] = (render.render(cfg.widgets_after, ctx))
  end

  parts[#parts + 1] = '%#TabLineFill#'

  return table.concat(parts)
end

local enabled = false
local saved_tabline
local saved_showtabline
local augroup

function M.enable()
  if enabled then
    return
  end
  enabled = true
  saved_tabline = vim.o.tabline
  saved_showtabline = vim.o.showtabline
  vim.o.tabline = "%{%v:lua.require'mep.chrome.tabline'.eval()%}"
  if vim.o.showtabline == 1 then
    vim.o.showtabline = 2
  end
  -- A bare mode change (`i`, `<Esc>`, `<C-v>`, ...) doesn't otherwise
  -- necessarily trigger a screen redraw on its own — unlike typing text
  -- or moving the cursor, nothing about the *buffer* changed, so
  -- Neovim has no reason to think the tabline (or, for that matter,
  -- anything else) needs re-evaluating — confirmed the hard way: the
  -- default mode-indicator widget (`mep.chrome.mode`) sat on "Normal"
  -- well after actually entering Insert mode, until some *other* redraw
  -- (moving the cursor, say) happened to catch it up. `ModeChanged`
  -- fires for every mode transition, generic across whatever `mode()`
  -- reports; forcing a `:redrawtabline` there keeps any mode-dependent
  -- tabline content live, not just this module's own default widget.
  augroup = vim.api.nvim_create_augroup('MepChromeTablineMode', { clear = true })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = augroup,
    callback = function()
      vim.cmd('redrawtabline')
    end,
  })
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.o.tabline = saved_tabline
  vim.o.showtabline = saved_showtabline
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
end

function M._reset()
  M.disable()
end

return M

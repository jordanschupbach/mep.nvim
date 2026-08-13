--- mep.chrome's `'statusline'` target: a single global `%{%...%}`
--- funcref (`M.eval`, wired up as `v:lua.require(...).eval()` by `M.
--- enable`) that Neovim re-evaluates per window via `g:statusline_winid`
--- (`:help 'statusline'`) — one shared assignment renders every
--- window's bar with that window's own widget `ctx`, rather than this
--- module looping over windows itself.
local config = require('mep.chrome.config')
local render = require('mep.chrome.render')
local hover = require('mep.chrome.hover')

local M = {}

function M.eval()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
  local ctx = {
    win = win,
    bufnr = ok and bufnr or vim.api.nvim_get_current_buf(),
    active = win == vim.api.nvim_get_current_win(),
  }
  local text, ranges = render.render(config.options.statusline.widgets, ctx)
  hover.set_ranges('statusline', win, ranges)
  return text
end

local enabled = false
local saved_statusline
local saved_laststatus

function M.enable()
  if enabled then
    return
  end
  enabled = true
  saved_statusline = vim.o.statusline
  saved_laststatus = vim.o.laststatus
  vim.o.statusline = "%{%v:lua.require'mep.chrome.statusline'.eval()%}"
  if vim.o.laststatus == 0 then
    vim.o.laststatus = 2
  end
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.o.statusline = saved_statusline
  vim.o.laststatus = saved_laststatus
end

function M._reset()
  M.disable()
end

return M

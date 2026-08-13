--- mep.chrome's `'winbar'` target — same `%{%...%}` funcref-per-window
--- mechanism as `mep.chrome.statusline` (`:help 'winbar'`: "The value
--- of 'winbar' is evaluated like with 'statusline'", including
--- `g:statusline_winid`).
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
  local text, ranges = render.render(config.options.winbar.widgets, ctx)
  hover.set_ranges('winbar', win, ranges)
  return text
end

local enabled = false
local saved_winbar

function M.enable()
  if enabled then
    return
  end
  enabled = true
  saved_winbar = vim.o.winbar
  vim.o.winbar = "%{%v:lua.require'mep.chrome.winbar'.eval()%}"
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.o.winbar = saved_winbar
end

function M._reset()
  M.disable()
end

return M

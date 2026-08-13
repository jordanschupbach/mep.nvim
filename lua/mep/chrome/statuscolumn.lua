--- mep.chrome's `'statuscolumn'` target. Unlike statusline/winbar/
--- tabline, `'statuscolumn'` is re-evaluated once per *screen line*
--- (not per window) — `M.eval()` reads `vim.v.lnum`/`vim.v.relnum`/
--- `vim.v.virtnum` directly rather than emitting `%{}` sub-items for
--- them. `%s`/`%C` (Neovim's own sign/fold-column items) are passed
--- through literally when `signs`/`folds` are enabled — there's no
--- reasonable way to reimplement those ourselves. Per `:help
--- 'statuscolumn'`, a `%@` click function "will be the same for each
--- row in the same column" — mep.chrome.click's design (one shared
--- global dispatch function resolving the actual widget via `minwid`,
--- which *does* vary per call) already matches this constraint, so
--- `widgets`' own `on_click` works here unchanged.
local config = require('mep.chrome.config')
local render = require('mep.chrome.render')

local M = {}

function M.eval()
  local cfg = config.options.statuscolumn
  local parts = {}

  if cfg.signs then
    parts[#parts + 1] = '%s'
  end
  if cfg.folds then
    parts[#parts + 1] = '%C'
  end
  if cfg.numbers then
    parts[#parts + 1] = '%='
    if vim.v.virtnum ~= 0 then
      parts[#parts + 1] = ' '
    elseif vim.wo.relativenumber and vim.v.relnum ~= 0 then
      parts[#parts + 1] = vim.v.relnum .. ' '
    else
      parts[#parts + 1] = vim.v.lnum .. ' '
    end
  end

  if #cfg.widgets > 0 then
    local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
    local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
    local ctx = {
      win = win,
      bufnr = ok and bufnr or vim.api.nvim_get_current_buf(),
      lnum = vim.v.lnum,
    }
    parts[#parts + 1] = (render.render(cfg.widgets, ctx))
  end

  return table.concat(parts)
end

local enabled = false
local saved_statuscolumn

function M.enable()
  if enabled then
    return
  end
  enabled = true
  saved_statuscolumn = vim.o.statuscolumn
  vim.o.statuscolumn = "%{%v:lua.require'mep.chrome.statuscolumn'.eval()%}"
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.o.statuscolumn = saved_statuscolumn
end

function M._reset()
  M.disable()
end

return M

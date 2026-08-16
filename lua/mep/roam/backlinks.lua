--- The backlinks panel: a single `mep.sidebar` instance (like `mep.
--- symbols`' own outline — one at a time, tied to whichever buffer it
--- was opened for) listing every note that links to the current note's
--- own ID (`mep.roam.scan.find_backlinks`). `<CR>` (via `mep.sidebar`'s
--- own built-in widget click) jumps to the linking headline.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.roam.config')
local notes = require('mep.roam.notes')
local scan = require('mep.roam.scan')

local M = {}

local instance
local target_bufnr

local function open_at(sidebar, path, lnum)
  if sidebar.target_win and vim.api.nvim_win_is_valid(sidebar.target_win) then
    vim.api.nvim_set_current_win(sidebar.target_win)
  end
  pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
end

--- This panel's `mep.sidebar` sections for whichever buffer `target_bufnr`
--- currently points at (set by `open()`/`toggle()`/`refresh()`).
function M.sections()
  local widgets = {}
  if not target_bufnr or not vim.api.nvim_buf_is_valid(target_bufnr) then
    widgets = { { id = '__none__', text = 'No note buffer' } }
  else
    local id = notes.id(target_bufnr)
    if not id then
      widgets = { { id = '__none__', text = 'Current note has no headline/ID yet' } }
    else
      for _, link in ipairs(scan.find_backlinks(config.options.roam_dirs, id)) do
        widgets[#widgets + 1] = {
          id = link.path .. ':' .. link.lnum,
          text = string.format('%s (%s)', link.title, vim.fn.fnamemodify(link.path, ':t')),
          on_click = function(_, sidebar)
            open_at(sidebar, link.path, link.lnum)
          end,
        }
      end
      if #widgets == 0 then
        widgets = { { id = '__none__', text = 'No backlinks' } }
      end
    end
  end
  return { { id = 'backlinks', title = 'Backlinks', widgets = widgets } }
end

local function redraw()
  if instance then
    instance:set_sections(M.sections())
  end
end

--- The underlying `mep.sidebar` instance, building it (closed) the
--- first time it's needed — public (like `mep.dap.sidebar.panel()`) so
--- external code (or a test) can inspect `.buf`/`.win` directly, since
--- `focus = false` below means the sidebar's own window is never
--- necessarily the current one after `open()`.
function M.panel()
  if not instance then
    instance = sidebar_mod.new({
      title = 'Roam Backlinks',
      position = config.options.sidebar.position,
      width = config.options.sidebar.width,
      height = config.options.sidebar.height,
      border = config.options.sidebar.border,
      animate = config.options.sidebar.animate,
      float = true,
      focus = false,
      sections = M.sections(),
    })
  end
  return instance
end

--- Recompute for whichever buffer is current right now, re-rendering
--- an already-open panel (a no-op if it isn't open).
function M.refresh()
  target_bufnr = vim.api.nvim_get_current_buf()
  redraw()
end

function M.open()
  target_bufnr = vim.api.nvim_get_current_buf()
  M.panel():open()
  redraw()
end

function M.close()
  if instance then
    instance:close()
  end
end

function M.toggle()
  target_bufnr = vim.api.nvim_get_current_buf()
  M.panel():toggle()
  redraw()
end

function M.is_open()
  return instance ~= nil and instance:is_open()
end

--- Test/dev-only: close and forget the panel instance, so the next
--- `panel()` call builds fresh.
function M._reset()
  if instance then
    pcall(function()
      instance:close()
    end)
  end
  instance = nil
  target_bufnr = nil
end

return M

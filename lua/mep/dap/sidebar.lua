--- The debug panel: a single `mep.sidebar` instance (like `mep.symbols`'
--- own outline — one at a time, not `mep.git.sidebar`'s dock/split pair,
--- since there's no "pin it as a split in the current buffer" use case
--- here the way there is for a status list) showing the current call
--- stack, the top frame's scopes/variables, and every recorded
--- breakpoint. Redraws itself on `mep.dap.session.subscribe` events and
--- `mep.dap.breakpoints.on_change`. `M.toggle_layout` pairs this panel
--- (left, by default) with `mep.dap.repl`'s own bottom-split debug
--- console, so one keymap opens/closes the whole dap-ui-like layout.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.dap.config')
local session = require('mep.dap.session')
local breakpoints = require('mep.dap.breakpoints')
local repl = require('mep.dap.repl')

local M = {}

local instance
local subscribed = false

local function open_at(path, lnum)
  if instance and instance.target_win and vim.api.nvim_win_is_valid(instance.target_win) then
    vim.api.nvim_set_current_win(instance.target_win)
  end
  if path then
    pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(path))
  end
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
  end
end

local function frame_label(frame)
  local where = ''
  if frame.source and frame.source.path then
    where = string.format(' (%s:%d)', vim.fn.fnamemodify(frame.source.path, ':t'), frame.line or 0)
  end
  return (frame.name or '?') .. where
end

local function stack_widgets()
  if #session.stack_frames == 0 then
    return { { id = '__none__', text = 'No active session' } }
  end
  local widgets = {}
  for _, frame in ipairs(session.stack_frames) do
    widgets[#widgets + 1] = {
      id = 'frame:' .. tostring(frame.id),
      text = frame_label(frame),
      on_click = function()
        if frame.source and frame.source.path then
          open_at(frame.source.path, frame.line)
        end
      end,
    }
  end
  return widgets
end

local function variable_widgets(var_ref, indent)
  local widgets = {}
  for _, var in ipairs(session.variables[var_ref] or {}) do
    widgets[#widgets + 1] = {
      id = 'var:' .. tostring(var_ref) .. ':' .. var.name,
      text = indent .. var.name .. ' = ' .. tostring(var.value),
    }
  end
  return widgets
end

local function scope_widgets()
  if #session.scopes == 0 then
    return { { id = '__none__', text = '(no scopes)' } }
  end
  local widgets = {}
  for _, scope in ipairs(session.scopes) do
    widgets[#widgets + 1] = { id = 'scope:' .. scope.name, text = scope.name }
    vim.list_extend(widgets, variable_widgets(scope.variablesReference, '  '))
  end
  return widgets
end

local function breakpoint_widgets()
  local all = breakpoints.all()
  if #all == 0 then
    return { { id = '__none__', text = 'No breakpoints' } }
  end
  local widgets = {}
  for _, entry in ipairs(all) do
    for _, lnum in ipairs(entry.lnums) do
      widgets[#widgets + 1] = {
        id = entry.path .. ':' .. lnum,
        text = string.format('%s:%d', vim.fn.fnamemodify(entry.path, ':t'), lnum),
        on_click = function()
          open_at(entry.path, lnum)
        end,
      }
    end
  end
  return widgets
end

--- This panel's `mep.sidebar` sections, built fresh from `mep.dap.
--- session`'s current state and `mep.dap.breakpoints.all()` every call
--- — both plain in-memory reads, so building sections never blocks.
function M.sections()
  return {
    { id = 'stack', title = string.format('Call Stack (%s)', session.status), widgets = stack_widgets() },
    { id = 'scopes', title = 'Scopes', widgets = scope_widgets() },
    { id = 'breakpoints', title = 'Breakpoints', widgets = breakpoint_widgets() },
  }
end

local function redraw()
  if instance then
    instance:set_sections(M.sections())
  end
end

local function ensure_subscribed()
  if subscribed then
    return
  end
  subscribed = true
  session.subscribe(redraw)
  breakpoints.on_change(redraw)
end

--- The underlying `mep.sidebar` instance, building it (closed) the
--- first time it's needed — public (like `mep.git.sidebar.dock()`) so
--- external code (or a test) can inspect `.buf`/`.win` directly, since
--- `focus = false` below means the sidebar's own window is never
--- necessarily the current one after `open()`.
function M.panel()
  ensure_subscribed()
  if not instance then
    instance = sidebar_mod.new({
      title = 'Debug',
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

function M.open()
  M.panel():open()
  redraw()
end

function M.close()
  if instance then
    instance:close()
  end
end

function M.toggle()
  M.panel():toggle()
  redraw()
end

function M.is_open()
  return instance ~= nil and instance:is_open()
end

--- The dap-ui-like combined layout toggle: this panel (left) and `mep.
--- dap.repl`'s debug console (bottom split) open/close together —
--- idempotent regardless of which combination is currently open, since
--- either one being open already means "the layout is up", so a press
--- closes both rather than only bringing the other one in sync.
function M.toggle_layout()
  if M.is_open() or repl.is_open() then
    M.close()
    repl.close()
  else
    M.open()
    repl.open()
  end
end

--- Test/dev-only: close and forget the panel instance and its
--- subscriptions, so the next `panel()` call builds fresh.
function M._reset()
  if instance then
    pcall(function()
      instance:close()
    end)
  end
  instance = nil
  subscribed = false
end

return M

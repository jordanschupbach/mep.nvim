--- Breakpoint bookkeeping and gutter signs: session-only (in-memory, not
--- persisted to disk — real launch configs vary too much per project for
--- this to guess a sensible store location), keyed by each file's
--- absolute path so a breakpoint set once shows up again in every buffer
--- that later opens the same file. `mep.dap.session` (not this module)
--- is what actually pushes the current set to a running adapter via
--- `setBreakpoints` — this module only owns "where are they" and "how do
--- they render"; `M.on_change` is the seam between the two.
local config = require('mep.dap.config')

local M = {}

local sign_ns = vim.api.nvim_create_namespace('mep_dap_breakpoints')
local augroup = nil

--- Give MepDapBreakpoint a visible default if nothing else already has
--- — `default = true` means a user's own `:highlight MepDapBreakpoint
--- ...` (or a colorscheme that defines it) wins over this.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, 'MepDapBreakpoint', { link = 'DiagnosticError', default = true })
end
M.define_default_hl()

-- absolute path -> { [lnum] = true }
local by_path = {}
local change_listeners = {}

local function abs_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

--- Register `fn(path, lnums)` to be called after every mutation
--- (toggle/clear/clear_all) — `lnums` is the sorted list of remaining
--- breakpoint lines for `path` (possibly empty).
function M.on_change(fn)
  change_listeners[#change_listeners + 1] = fn
end

local function sorted_lnums(path)
  local set = by_path[path]
  if not set then
    return {}
  end
  local lnums = vim.tbl_keys(set)
  table.sort(lnums)
  return lnums
end

local function notify_change(path)
  local lnums = sorted_lnums(path)
  for _, fn in ipairs(change_listeners) do
    fn(path, lnums)
  end
end

--- Every breakpoint line (sorted) recorded for `bufnr`'s file — `{}` for
--- an unnamed buffer or one with none set.
function M.list(bufnr)
  local path = abs_path(bufnr)
  if not path then
    return {}
  end
  return sorted_lnums(path)
end

--- Place sign-column extmarks for every breakpoint recorded against
--- `bufnr`'s file, replacing whatever this module had rendered there
--- before. A no-op for an unnamed or invalid buffer.
function M.render(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, sign_ns, 0, -1)
  local sign = config.options.signs.breakpoint
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, lnum in ipairs(M.list(bufnr)) do
    if lnum >= 1 and lnum <= line_count then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, sign_ns, lnum - 1, 0, {
        sign_text = sign.text,
        sign_hl_group = sign.hl,
      })
    end
  end
end

--- Toggle a breakpoint at `lnum` in `bufnr`'s file, re-render its signs,
--- and notify `M.on_change` listeners. Returns whether a breakpoint is
--- now set there (`false` for an unnamed buffer — nothing to key it by).
function M.toggle(bufnr, lnum)
  local path = abs_path(bufnr)
  if not path then
    return false
  end
  by_path[path] = by_path[path] or {}
  local now_set
  if by_path[path][lnum] then
    by_path[path][lnum] = nil
    now_set = false
  else
    by_path[path][lnum] = true
    now_set = true
  end
  M.render(bufnr)
  notify_change(path)
  return now_set
end

--- Remove every breakpoint recorded for `bufnr`'s file, re-render (now
--- empty), and notify listeners.
function M.clear(bufnr)
  local path = abs_path(bufnr)
  if not path then
    return
  end
  by_path[path] = nil
  M.render(bufnr)
  notify_change(path)
end

--- Remove every breakpoint across every file. Doesn't touch any
--- buffer's signs directly (there's no bufnr to key off of here) —
--- callers that want the gutter to reflect this immediately should
--- `render()` whichever buffers are open themselves.
function M.clear_all()
  local paths = vim.tbl_keys(by_path)
  by_path = {}
  for _, path in ipairs(paths) do
    notify_change(path)
  end
end

--- Every path with at least one breakpoint, each paired with its sorted
--- line list — what `mep.dap.session` walks to seed a freshly-started
--- adapter via `setBreakpoints`.
function M.all()
  local result = {}
  for path in pairs(by_path) do
    result[#result + 1] = { path = path, lnums = sorted_lnums(path) }
  end
  table.sort(result, function(a, b)
    return a.path < b.path
  end)
  return result
end

--- Start rendering `bufnr` automatically: an immediate `render()`, plus
--- re-rendering on `BufReadPost` (a file with recorded breakpoints,
--- reopened in a new buffer, shows them without an explicit call) and
--- teardown on `BufDelete`. No debounce, unlike `mep.git.gutter`'s own
--- attach/detach lifecycle — placing a handful of static signs is O(1)
--- work, nothing here is expensive enough to need coalescing.
function M.attach(bufnr)
  M.render(bufnr)
  if not augroup then
    augroup = vim.api.nvim_create_augroup('MepDapBreakpoints', { clear = true })
  end
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      M.render(bufnr)
    end,
  })
end

--- Stop the autocmds `attach` registered for `bufnr` (its signs stay
--- until the buffer itself goes away — this only stops future
--- re-renders).
function M.detach(bufnr)
  if augroup then
    vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
  end
end

return M

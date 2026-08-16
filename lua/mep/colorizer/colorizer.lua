--- Aggregator and per-buffer lifecycle for mep's colorizer: detects
--- `#rgb`/`#rrggbb`/`#rrggbbaa`, `rgb()`/`rgba()`, and CSS named colors
--- (`mep.colorizer.patterns`) in any buffer, rendering a background
--- swatch or an inline swatch character (`mep.colorizer.ui`) via
--- extmarks. Attach/detach lifecycle mirrors `mep.markdown.gutter`'s
--- own (debounced recompute on `TextChanged`/`TextChangedI`/
--- `BufWritePost`); the global `enable()`/`disable()` auto-attach-by-
--- filetype wiring mirrors `mep.git.gutter`'s own.
local core = require('mep.core')
local config = require('mep.colorizer.config')
local ui = require('mep.colorizer.ui')

local M = {}

local state = {} -- bufnr -> { debounced, timer, augroup }
local global_augroup = nil

local function filetype_matches(bufnr)
  local filetypes = config.options.filetypes
  if not filetypes or #filetypes == 0 then
    return true
  end
  return vim.tbl_contains(filetypes, vim.bo[bufnr].filetype)
end

local function render(bufnr)
  ui.render(bufnr, config.options.mode, config.options.swatch_char)
end

--- Start tracking `bufnr`: render now, and keep it up to date (debounced)
--- as the buffer changes. A no-op if `bufnr`'s filetype isn't in
--- `config.options.filetypes` (when that's set), or it's already
--- attached.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] or not filetype_matches(bufnr) then
    return
  end

  local debounced, timer = core.util.debounce(function()
    render(bufnr)
  end, config.options.debounce_ms)

  local grp = vim.api.nvim_create_augroup('MepColorizer' .. bufnr, { clear = true })
  state[bufnr] = { debounced = debounced, timer = timer, augroup = grp }

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
    group = grp,
    buffer = bufnr,
    callback = debounced,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = grp,
    buffer = bufnr,
    once = true,
    callback = function()
      M.detach(bufnr)
    end,
  })

  render(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- extmarks. Safe to call on a buffer that was never attached.
function M.detach(bufnr)
  local st = state[bufnr]
  if not st then
    return
  end
  if st.timer then
    pcall(function()
      st.timer:stop()
      st.timer:close()
    end)
  end
  if st.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, st.augroup)
  end
  ui.clear(bufnr)
  state[bufnr] = nil
end

function M.is_attached(bufnr)
  return state[bufnr] ~= nil
end

--- Register the global `BufEnter`/`BufReadPost` autocmd that `attach`es
--- every buffer whose filetype matches, and attach every already-loaded
--- matching one right away (a `setup()` after buffers are already open
--- shouldn't need them reopened to pick up highlighting).
function M.enable()
  M.disable()
  global_augroup = vim.api.nvim_create_augroup('MepColorizer', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufReadPost' }, {
    group = global_augroup,
    callback = function(args)
      M.attach(args.buf)
    end,
  })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.attach(bufnr)
    end
  end
end

--- Undo `enable()`: stop listening for new buffers and `detach` every
--- currently-attached one.
function M.disable()
  if global_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, global_augroup)
    global_augroup = nil
  end
  local attached = {}
  for bufnr in pairs(state) do
    attached[#attached + 1] = bufnr
  end
  for _, bufnr in ipairs(attached) do
    M.detach(bufnr)
  end
end

--- Configure mep.colorizer: `mode` (`'background'`/`'swatch'`),
--- `swatch_char`, `filetypes` (`false` for every filetype), and
--- `debounce_ms` — see mep.colorizer.config.defaults. Calls `M.enable()`
--- unconditionally, same as `mep.git`'s own `enable = true`-by-default
--- posture — pass `filetypes = { ... }` to scope it down, there's no
--- separate opt-out flag.
function M.setup(opts)
  local options = config.setup(opts)
  M.enable()
  return options
end

--- Test/dev-only: drop all state (as `disable()`).
function M._reset()
  M.disable()
end

return M

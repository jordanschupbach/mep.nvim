--- Aggregator and controller for mep's LSP-backed symbols outline: a
--- single persistent panel (like mep.filetree, only one at a time)
--- showing whichever client attached to the current buffer reports for
--- `textDocument/documentSymbol` — classes/methods/functions/variables/
--- enums/etc, filetype-specific purely because that's whatever the
--- attached server understands for that filetype. `<CR>` jumps to the
--- symbol under the cursor, in the buffer the outline was opened for.
local config = require('mep.symbols.config')
local lsp = require('mep.symbols.lsp')
local ui = require('mep.symbols.ui')

local M = {}

local state = {
  win = nil,
  buf = nil,
  target_win = nil,
  target_buf = nil,
  activatable = {},
  augroup = nil,
}

--- Configure the symbols library. See mep.symbols.config.defaults for
--- width_ratio/min_width/position/keymaps/triggers. Works with sensible
--- defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.triggers.toggle) do
    vim.keymap.set('n', lhs, function()
      M.toggle()
    end, { desc = 'mep.symbols: toggle the symbols outline for the current buffer' })
  end
  return options
end

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end
M.is_open = is_open

local function render(symbols, err)
  state.activatable = ui.render(state.buf, symbols, err)
end

--- Re-request symbols for `state.target_buf` and re-render. A no-op if
--- the panel isn't open, or the buffer it was opened for is gone.
function M.refresh()
  if not is_open() then
    return
  end
  if not state.target_win or not vim.api.nvim_win_is_valid(state.target_win) then
    render(nil, 'the window this outline was opened for is gone')
    return
  end
  local target_buf = state.target_buf
  lsp.request(target_buf, function(symbols, err)
    vim.schedule(function()
      -- The panel may have closed, or been reopened for a different
      -- buffer, while this request was in flight.
      if is_open() and state.target_buf == target_buf then
        render(symbols, err)
      end
    end)
  end)
end

local function symbol_at_cursor()
  if not is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.activatable[lnum]
end

local function jump_to_symbol_at_cursor()
  local sym = symbol_at_cursor()
  if not sym then
    return
  end
  if not state.target_win or not vim.api.nvim_win_is_valid(state.target_win) then
    return
  end
  vim.api.nvim_set_current_win(state.target_win)
  pcall(vim.api.nvim_win_set_cursor, state.target_win, { sym.lnum, sym.col })
end

local function bind_keymaps()
  local km = config.options.keymaps
  local map_opts = { buffer = state.buf, nowait = true, silent = true }
  local function map_all(lhs_list, fn, desc)
    local opts = vim.tbl_extend('force', map_opts, { desc = desc })
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, fn, opts)
    end
  end
  map_all(km.jump, jump_to_symbol_at_cursor, 'mep.symbols: jump to symbol under cursor')
  map_all(km.close, M.close, 'mep.symbols: close')
  map_all(km.refresh, M.refresh, 'mep.symbols: refresh')
end

local function bind_autocmds()
  state.augroup = vim.api.nvim_create_augroup('MepSymbols', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = state.augroup,
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
      if state.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
        state.augroup = nil
      end
    end,
  })
  -- Keep the outline in sync with the buffer it was opened for, without
  -- requiring an explicit `R` after every edit.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = state.augroup,
    buffer = state.target_buf,
    callback = M.refresh,
  })
end

--- Open the outline for the current buffer (no-op if already open).
--- Width is `config.options.width_ratio` (floored, at least
--- `config.options.min_width`) of the *current* window's width, and the
--- split is scoped to that window (`aboveleft`/`belowright vertical N
--- split`, not `topleft`/`botright`) — the outline pops up next to
--- whatever buffer it's showing, rather than annexing the whole
--- tabpage's edge the way mep.filetree's single persistent tree panel
--- does; this one is tied to one specific buffer's symbols, not a
--- project-wide view.
function M.open()
  if is_open() then
    return
  end

  local target_win = vim.api.nvim_get_current_win()
  local target_buf = vim.api.nvim_win_get_buf(target_win)
  local width =
    math.max(config.options.min_width, math.floor(vim.api.nvim_win_get_width(target_win) * config.options.width_ratio))

  state.target_win = target_win
  state.target_buf = target_buf
  state.buf, state.win = ui.create_window(width, config.options.position)

  bind_keymaps()
  bind_autocmds()

  render(nil, 'Loading symbols…')
  M.refresh()
end

--- Close the outline (no-op if not open). Actual teardown (state,
--- augroup) happens in the `WinClosed` handler `open()` registers, so
--- closing the window through any means (this method, `q`, `<C-w>c`,
--- `:close`) stays consistent.
function M.close()
  if not is_open() then
    return
  end
  ui.close_window(state.win)
end

function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

return M

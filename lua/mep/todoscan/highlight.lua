--- Debounced, per-buffer live highlighting of TODO/FIXME/HACK/NOTE-style
--- comments — a sign-column glyph plus a highlight group per keyword on
--- the matched word itself. Same "debounced attach/detach lifecycle"
--- idiom `mep.git.gutter` uses (recompute on text change/save, torn
--- down on `BufDelete`/`BufWipeout`) — but pure buffer-local text
--- scanning (`mep.todoscan.scan.match_line`), no external process
--- involved the way the project-wide `mep.todoscan.picker` needs one.
local core = require('mep.core')
local config = require('mep.todoscan.config')
local scan = require('mep.todoscan.scan')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_todoscan')

-- bufnr -> { debounced, timer, augroup }
local state = {}
local augroup = nil

-- Default base highlight to link a keyword's own `MepTodoScan<Keyword>`
-- group to, and its default 2-cell sign glyph — both overridable
-- per-keyword (signs via `config.options.signs`), and both fall back to
-- a generic default for any keyword beyond these four.
local BASE_HL = { TODO = 'DiagnosticWarn', FIXME = 'DiagnosticError', HACK = 'DiagnosticInfo', NOTE = 'DiagnosticHint' }
local SIGN_TEXT = { TODO = 'TD', FIXME = 'FX', HACK = 'HK', NOTE = 'NT' }

--- The `MepTodoScan<Keyword>` highlight group name for `keyword`
--- (title-cased: `'FIXME'` -> `'MepTodoScanFixme'`) — the exact four
--- names the TODO this library implements specifies for the default
--- keyword set, derived the same way for any custom keyword added via
--- `config.options.keywords` too.
local function hl_group(keyword)
  return 'MepTodoScan' .. keyword:sub(1, 1):upper() .. keyword:sub(2):lower()
end
M.hl_group = hl_group

--- Link `keyword`'s own highlight group to a sensible built-in default
--- (`default = true`: a no-op wherever the colorscheme, or an earlier
--- call, already defined one) — every call, not just once, so it's
--- reapplied on a real `:colorscheme` change the same way every other
--- Mep* group in `plugin/mep.lua` is (this module additionally defines
--- the canonical four itself so they still look right under the
--- busted/nlua test harness, which never loads that file).
local function define_highlight(keyword)
  local group = hl_group(keyword)
  vim.api.nvim_set_hl(0, group, { link = BASE_HL[keyword] or 'DiagnosticHint', default = true })
  return group
end

local function sign_text(keyword)
  return config.options.signs[keyword] or SIGN_TEXT[keyword] or keyword:sub(1, 2):upper()
end

local function clear_signs(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

--- Recompute `bufnr`'s own signs/highlights right now (the debounced
--- autocmd handler calls straight into this once its timer fires). A
--- no-op if `bufnr` was never `attach`ed.
function M.recompute(bufnr)
  if not state[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  clear_signs(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    local keyword, col_start, col_end = scan.match_line(line, config.options.keywords)
    if keyword then
      local group = define_highlight(keyword)
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, col_start, {
        end_col = col_end,
        hl_group = group,
        sign_text = sign_text(keyword),
        sign_hl_group = group,
      })
    end
  end
end

--- Start tracking `bufnr`: bind its own buffer-local recompute
--- autocmds and run an initial `recompute`. Safe to call more than
--- once for the same buffer — already-attached is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] or vim.bo[bufnr].buftype ~= '' then
    return
  end

  local debounced, timer = core.util.debounce(function()
    M.recompute(bufnr)
  end, config.options.debounce_ms)

  local grp = vim.api.nvim_create_augroup('MepTodoScan' .. bufnr, { clear = true })
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

  M.recompute(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- signs/highlights. Safe to call on a buffer that was never attached.
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
  clear_signs(bufnr)
  state[bufnr] = nil
end

--- Register the global `BufEnter`/`BufReadPost` autocmd that `attach`es
--- every normal, file-backed buffer, and attach every already-loaded
--- one right away.
function M.enable()
  M.disable()
  augroup = vim.api.nvim_create_augroup('MepTodoScanGlobal', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufReadPost' }, {
    group = augroup,
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
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  local attached = {}
  for bufnr in pairs(state) do
    attached[#attached + 1] = bufnr
  end
  for _, bufnr in ipairs(attached) do
    M.detach(bufnr)
  end
end

--- Test/dev-only: drop all state (as `disable()`).
function M._reset()
  M.disable()
end

return M

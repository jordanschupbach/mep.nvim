--- Per-buffer git gutter: attaches to file-backed buffers inside a git
--- repo, keeps `mep.git.diff`-computed hunks up to date (debounced, on
--- text change / save) as sign-column extmarks, and drives hunk
--- navigation (`]c`/`[c`) plus the stage/reset/preview-hunk actions.
--- Diffing itself lives in `mep.git.diff`; this module owns the
--- per-buffer bookkeeping (state, autocmds, signs, keymaps) around it.
local core = require('mep.core')
local config = require('mep.git.config')
local diff = require('mep.git.diff')

local M = {}

local sign_ns = vim.api.nvim_create_namespace('mep_git_gutter')
local preview_ns = vim.api.nvim_create_namespace('mep_git_gutter_preview')

-- bufnr -> { root, relpath, indexed_lines, hunks, debounced, timer, augroup }
local state = {}
local augroup = nil
local on_change_callbacks = {}

--- `bufnr`'s absolute path, relative to `root` — nil if it isn't
--- actually under `root` (shouldn't happen: `root` is found by walking
--- up *from* this same buffer's directory) or the buffer has no name.
local function relpath(root, bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  name = vim.fn.fnamemodify(name, ':p')
  local prefix = root .. '/'
  if name:sub(1, #prefix) == prefix then
    return name:sub(#prefix + 1)
  end
  return nil
end

local function buffer_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

local function clear_signs(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, sign_ns, 0, -1)
  end
end

local function place_signs(bufnr, hunks)
  clear_signs(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, hunk in ipairs(hunks) do
    for _, sr in ipairs(diff.sign_rows(hunk)) do
      if sr.row >= 1 and sr.row <= line_count then
        local sign = config.options.signs[sr.kind]
        if sign then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, sign_ns, sr.row - 1, 0, {
            sign_text = sign.text,
            sign_hl_group = sign.hl,
          })
        end
      end
    end
  end
end

--- The buffer-side (1-based) row `hunk` is jumped/anchored to: its
--- first added/changed row, or (for a pure delete, which has no row of
--- its own) the row the deletion sits at — the same anchor `M.
--- sign_rows` places a delete's single sign on.
function M.hunk_start_row(hunk)
  if hunk.count_b > 0 then
    return hunk.start_b
  end
  return hunk.start_b == 0 and 1 or hunk.start_b
end

local function hunk_at(bufnr, lnum)
  for _, h in ipairs(M.get_hunks(bufnr)) do
    local row = M.hunk_start_row(h)
    local span = math.max(h.count_b, 1)
    if lnum >= row and lnum < row + span then
      return h
    end
  end
  return nil
end

--- Recompute hunks/signs for `bufnr` right now (the debounced autocmd
--- handler calls straight into this once its timer fires). A no-op if
--- `bufnr` was never `attach`ed, or was `detach`ed while the `git show`
--- fetching its indexed content was still in flight.
function M.recompute(bufnr)
  local st = state[bufnr]
  if not st or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  diff.get_indexed_content(st.root, st.relpath, function(content)
    if not state[bufnr] then
      return
    end
    st.indexed_lines = diff.split_lines(content)
    local hunks = diff.compute_hunks(content, buffer_text(bufnr))
    st.hunks = hunks
    place_signs(bufnr, hunks)
    for _, cb in ipairs(on_change_callbacks) do
      cb(bufnr)
    end
  end)
end

local function bind_keymaps(bufnr)
  local km = config.options.keymaps
  local map_opts = { buffer = bufnr, silent = true }
  local function map_all(lhs_list, fn, desc)
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, fn, vim.tbl_extend('force', map_opts, { desc = desc }))
    end
  end
  map_all(km.next_hunk, function()
    M.next_hunk()
  end, 'mep.git: next hunk')
  map_all(km.prev_hunk, function()
    M.prev_hunk()
  end, 'mep.git: previous hunk')
  map_all(km.stage_hunk, function()
    M.stage_hunk(bufnr)
  end, 'mep.git: stage hunk')
  map_all(km.reset_hunk, function()
    M.reset_hunk(bufnr)
  end, 'mep.git: reset hunk')
  map_all(km.preview_hunk, function()
    M.preview_hunk(bufnr)
  end, 'mep.git: preview hunk')
end

local function unbind_keymaps(bufnr)
  local km = config.options.keymaps
  for _, list in pairs(km) do
    for _, lhs in ipairs(list) do
      pcall(vim.keymap.del, 'n', lhs, { buffer = bufnr })
    end
  end
end

--- Start tracking `bufnr`: resolve its git root/relpath (a no-op if
--- either fails — not inside a git repo, or an unnamed/scratch/special
--- buffer), bind the hunk-nav/action keymaps, register its own
--- buffer-local recompute autocmds, and run an initial `recompute`.
--- Safe to call more than once for the same buffer — already-attached
--- is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] or vim.bo[bufnr].buftype ~= '' then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return
  end
  local root = core.util.find_root(vim.fn.fnamemodify(name, ':p:h'))
  if vim.fn.isdirectory(root .. '/.git') == 0 and vim.fn.filereadable(root .. '/.git') == 0 then
    return -- find_root() just hands back its input when no `.git` is found
  end
  local rel = relpath(root, bufnr)
  if not rel then
    return
  end

  local debounced, timer = core.util.debounce(function()
    M.recompute(bufnr)
  end, config.options.debounce_ms)

  local grp = vim.api.nvim_create_augroup('MepGitGutter' .. bufnr, { clear = true })
  state[bufnr] = {
    root = root,
    relpath = rel,
    hunks = {},
    indexed_lines = {},
    debounced = debounced,
    timer = timer,
    augroup = grp,
  }

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

  bind_keymaps(bufnr)
  M.recompute(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds/keymaps and
--- clear its signs. Safe to call on a buffer that was never attached.
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
  unbind_keymaps(bufnr)
  clear_signs(bufnr)
  state[bufnr] = nil
end

--- The last-computed hunk list for `bufnr` — empty if never attached,
--- or attached but not yet resolved/nothing changed.
function M.get_hunks(bufnr)
  local st = state[bufnr]
  return st and st.hunks or {}
end

--- `bufnr`'s repo root/relpath, or nil if it isn't attached — `mep.git.
--- sidebar` uses this to resolve the "current file" for its hunks
--- section without duplicating `attach`'s own root/relpath resolution.
function M.info(bufnr)
  local st = state[bufnr]
  if not st then
    return nil
  end
  return { root = st.root, relpath = st.relpath }
end

--- Register `cb(bufnr)` to run every time `bufnr`'s hunks are
--- recomputed — `mep.git.sidebar` subscribes once to keep its "current
--- file" hunk section live without polling.
function M.on_change(cb)
  on_change_callbacks[#on_change_callbacks + 1] = cb
end

local function jump(win, forward)
  win = win or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  local hunks = M.get_hunks(bufnr)
  if #hunks == 0 then
    return
  end
  local rows = {}
  for _, h in ipairs(hunks) do
    rows[#rows + 1] = M.hunk_start_row(h)
  end
  table.sort(rows)
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  if forward then
    for _, row in ipairs(rows) do
      if row > cur then
        vim.api.nvim_win_set_cursor(win, { row, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(win, { rows[1], 0 })
  else
    for i = #rows, 1, -1 do
      if rows[i] < cur then
        vim.api.nvim_win_set_cursor(win, { rows[i], 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(win, { rows[#rows], 0 })
  end
end

--- Jump the cursor in `win` (current window by default) to the next
--- hunk after it, wrapping around to the first hunk if it's already
--- past the last one.
function M.next_hunk(win)
  jump(win, true)
end

--- `next_hunk`, backwards.
function M.prev_hunk(win)
  jump(win, false)
end

--- Stage just `hunk` (the one under the cursor by default) via `git
--- apply --cached --unidiff-zero` fed a minimal patch built from it
--- (`mep.git.diff.build_patch`) over stdin. Recomputes on success.
function M.stage_hunk(bufnr, hunk)
  local st = state[bufnr]
  if not st then
    return
  end
  hunk = hunk or hunk_at(bufnr, vim.api.nvim_win_get_cursor(0)[1])
  if not hunk then
    return
  end
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local patch = diff.build_patch(st.relpath, st.indexed_lines, buffer_lines, hunk)
  local job = core.job.spawn({
    cmd = { 'git', 'apply', '--cached', '--unidiff-zero', '-' },
    cwd = st.root,
    on_exit = function(code)
      if code == 0 then
        M.recompute(bufnr)
      else
        vim.notify('mep.git: failed to stage hunk', vim.log.levels.WARN)
      end
    end,
  })
  vim.fn.chansend(job.id, patch)
  vim.fn.chanclose(job.id, 'stdin')
end

--- Revert `hunk` (the one under the cursor by default) directly in the
--- buffer, restoring its indexed content — no git call needed, this is
--- purely local text.
function M.reset_hunk(bufnr, hunk)
  local st = state[bufnr]
  if not st then
    return
  end
  hunk = hunk or hunk_at(bufnr, vim.api.nvim_win_get_cursor(0)[1])
  if not hunk then
    return
  end
  local restore = {}
  for i = 0, hunk.count_a - 1 do
    restore[#restore + 1] = st.indexed_lines[hunk.start_a + i] or ''
  end
  local from, to
  if hunk.count_b > 0 then
    from = hunk.start_b - 1
    to = from + hunk.count_b
  else
    from = hunk.start_b
    to = hunk.start_b
  end
  vim.api.nvim_buf_set_lines(bufnr, from, to, false, restore)
  M.recompute(bufnr)
end

--- Show `hunk` (the one under the cursor by default) as a small,
--- zero-context `-`/`+` diff in a floating window near the cursor,
--- closed on the next cursor move / insert / leaving the buffer.
function M.preview_hunk(bufnr, hunk)
  local st = state[bufnr]
  if not st then
    return
  end
  hunk = hunk or hunk_at(bufnr, vim.api.nvim_win_get_cursor(0)[1])
  if not hunk then
    return
  end
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local lines, hls = {}, {}
  for i = 0, hunk.count_a - 1 do
    lines[#lines + 1] = '-' .. (st.indexed_lines[hunk.start_a + i] or '')
    hls[#hls + 1] = 'DiffDelete'
  end
  for i = 0, hunk.count_b - 1 do
    lines[#lines + 1] = '+' .. (buffer_lines[hunk.start_b + i] or '')
    hls[#hls + 1] = 'DiffAdd'
  end
  if #lines == 0 then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for i, hl in ipairs(hls) do
    pcall(vim.api.nvim_buf_add_highlight, buf, preview_ns, hl, i - 1, 0, -1)
  end

  local width = 10
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = math.min(width, math.max(10, vim.o.columns - 4)),
    height = math.min(#lines, 15),
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave' }, {
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

--- Link the config's sign highlight groups to sensible built-in
--- defaults (`default = true`: a no-op wherever the colorscheme, or an
--- earlier call, already defined one) — so signs are visible out of
--- the box without requiring the user to define
--- `MepGitAdd`/`MepGitChange`/`MepGitDelete`/`MepGitChangeDelete`
--- themselves.
local function define_highlights()
  vim.api.nvim_set_hl(0, 'MepGitAdd', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'MepGitChange', { link = 'DiffChange', default = true })
  vim.api.nvim_set_hl(0, 'MepGitDelete', { link = 'DiffDelete', default = true })
  vim.api.nvim_set_hl(0, 'MepGitChangeDelete', { link = 'DiffChange', default = true })
end

--- Register the global `BufEnter`/`BufReadPost` autocmd that `attach`es
--- every normal, file-backed buffer, and attach every already-loaded
--- one right away (a `setup()` after buffers are already open
--- shouldn't need them reopened to pick up the gutter).
function M.enable()
  M.disable()
  define_highlights()
  augroup = vim.api.nvim_create_augroup('MepGit', { clear = true })
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

--- Test/dev-only: drop all state (as `disable()`), plus the `on_change`
--- subscriber list.
function M._reset()
  M.disable()
  on_change_callbacks = {}
end

return M

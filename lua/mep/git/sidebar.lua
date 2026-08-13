--- The git panel: a `mep.sidebar` instance showing project status
--- (staged/unstaged/untracked files) plus the current file's hunks
--- (from `mep.git.gutter`), in two presentations sharing the same
--- `sections()` content — `M.dock()` (a floating panel flush against
--- an editor edge, `mep.activitybar`'s own style) and `M.split()` (a
--- real vsplit/split, `mep.filetree`'s own style, "pops up as a split
--- in the current buffer") — opening one closes the other, since
--- they're the same panel in two clothes, not two independent panels.
--- Action keymaps (stage/unstage/discard/commit/refresh, `mep.git.
--- config.defaults.sidebar.keymaps`) are bound fresh every time either
--- one opens, on top of `mep.sidebar`'s own built-in `<CR>` (open the
--- file/hunk under the cursor) and `q` (close). `M.attach(sb)` lets any
--- other `mep.sidebar` instance (`mep.activitybar.git`'s own panel, for
--- one) in on the same `sections()`/redraw-on-change/action-keymap
--- machinery, so this content isn't only reachable through `M.dock()`/
--- `M.split()`.
local core = require('mep.core')
local sidebar_mod = require('mep.sidebar')
local config = require('mep.git.config')
local status = require('mep.git.status')
local gutter = require('mep.git.gutter')

local M = {}

local dock_sidebar, split_sidebar
-- Every mep.sidebar instance showing this content — dock_sidebar/
-- split_sidebar plus anything registered via M.attach (e.g. mep.
-- activitybar.git's own panel) — kept in sync by `redraw()`/`ensure_
-- subscribed()`'s on_change handler below.
local instances = {}
local subscribed = false

local function root()
  return core.util.find_root()
end

--- Whichever attached buffer some open instance was opened from (its
--- `target_win`'s current buffer), or the current buffer if none is
--- open — the buffer `sections()`'s hunks section shows.
local function target_bufnr()
  for _, sb in ipairs(instances) do
    if sb:is_open() and sb.target_win and vim.api.nvim_win_is_valid(sb.target_win) then
      return vim.api.nvim_win_get_buf(sb.target_win)
    end
  end
  return vim.api.nvim_get_current_buf()
end

local function open_at(sidebar, path, lnum)
  if sidebar.target_win and vim.api.nvim_win_is_valid(sidebar.target_win) then
    vim.api.nvim_set_current_win(sidebar.target_win)
  end
  if path then
    core.util.open_file(path, lnum)
  elseif lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
  end
end

local function file_widgets(list, id_prefix, file_root)
  local widgets = {}
  for _, entry in ipairs(list) do
    widgets[#widgets + 1] = {
      id = id_prefix .. entry.path,
      text = entry.code .. ' ' .. entry.path,
      on_click = function(_, sidebar)
        open_at(sidebar, file_root .. '/' .. entry.path)
      end,
    }
  end
  return widgets
end

--- This panel's `mep.sidebar` sections, from `mep.git.status`'s cache
--- (`status.refresh` is what keeps that current — see `M.refresh`) and
--- `target_bufnr()`'s `mep.git.gutter` hunk cache. Both are
--- synchronous/cached reads, so building sections never itself blocks
--- on a git subprocess.
function M.sections()
  local st = status.get()
  local file_root = st.root or root()

  local status_widgets = {}
  vim.list_extend(status_widgets, file_widgets(st.staged, 'staged:', file_root))
  vim.list_extend(status_widgets, file_widgets(st.unstaged, 'unstaged:', file_root))
  vim.list_extend(status_widgets, file_widgets(st.untracked, 'untracked:', file_root))
  if #status_widgets == 0 then
    status_widgets = { { id = '__clean__', text = 'Nothing to commit, working tree clean' } }
  end

  local bufnr = target_bufnr()
  local hunk_widgets = {}
  for i, hunk in ipairs(gutter.get_hunks(bufnr)) do
    local row = gutter.hunk_start_row(hunk)
    hunk_widgets[#hunk_widgets + 1] = {
      id = tostring(i),
      text = string.format('%s @ line %d', hunk.kind, row),
      on_click = function(_, sidebar)
        open_at(sidebar, nil, row)
      end,
    }
  end
  if #hunk_widgets == 0 then
    hunk_widgets = { { id = '__none__', text = 'No hunks in current file' } }
  end

  return {
    { id = 'status', title = 'Status', widgets = status_widgets },
    { id = 'hunks', title = 'Hunks (current file)', widgets = hunk_widgets },
  }
end

--- Re-render every instance (`instances`, regardless of whether it's
--- currently open — `set_sections` on a closed one just updates what it
--- shows next time it opens) from the current `sections()` — a plain
--- redraw, no fetching of its own.
local function redraw()
  local sections = M.sections()
  for _, sb in ipairs(instances) do
    sb:set_sections(sections)
  end
end

--- Redraw immediately from whatever's cached, then kick off a fresh
--- `mep.git.status.refresh` and redraw again once that resolves. The
--- action keymaps below all funnel through this after mutating
--- anything, so the panel never sits stale after a stage/unstage/
--- discard/commit.
function M.refresh()
  redraw()
  status.refresh(root(), redraw)
end

local function any_open()
  for _, sb in ipairs(instances) do
    if sb:is_open() then
      return true
    end
  end
  return false
end

local function ensure_subscribed()
  if subscribed then
    return
  end
  subscribed = true
  gutter.on_change(function()
    if any_open() then
      redraw()
    end
  end)
end

--- The `{ section_id, widget_id }` under the cursor in `sb` — nil if
--- it's not open, or the cursor isn't on a widget line. Reads only
--- `mep.sidebar`'s public fields (`sb.win`, `sb.activatable`), not any
--- of its `_`-prefixed internals.
local function widget_under_cursor(sb)
  if not sb:is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(sb.win)[1]
  local entry = sb.activatable[lnum]
  if not entry or entry.kind ~= 'widget' then
    return nil
  end
  return entry.widget_id
end

--- A status-section widget id (`"staged:path"`/`"unstaged:path"`/
--- `"untracked:path"`, from `file_widgets` above) split back into its
--- kind and path — nil/nil if `widget_id` is nil or isn't shaped like
--- one (e.g. a hunk-section widget, or the "nothing to commit"
--- placeholder).
local function parse_status_widget(widget_id)
  if not widget_id then
    return nil, nil
  end
  return widget_id:match('^(%a+):(.+)$')
end

--- The lines of a commit-message compose buffer, trimmed of leading/
--- trailing blank lines and joined with `\n` into the single string
--- `status.commit` takes as its `-m` argument (multi-line, same as a
--- real `git commit` message — `core.job.spawn` execs `git` directly,
--- no shell in between, so the embedded newlines reach `git` intact
--- rather than needing any escaping).
local function commit_message_from_lines(lines)
  local first, last = 1, #lines
  while first <= last and lines[first] == '' do
    first = first + 1
  end
  while last >= first and lines[last] == '' do
    last = last - 1
  end
  local trimmed = {}
  for i = first, last do
    trimmed[#trimmed + 1] = lines[i]
  end
  return table.concat(trimmed, '\n')
end

--- Swap `sb`'s window into a real, editable scratch buffer (`filetype
--- = 'gitcommit'`, for the same comment/subject-line highlighting a
--- real `git commit` editor session gets) to type a commit message
--- into, mirroring Vim's own write-and-quit/quit-without-writing
--- convention rather than inventing a new one: `ZZ` commits it, `ZQ`
--- cancels. A no-op if `sb` isn't open or a compose is already in
--- flight on it.
---
--- `sb.buf` (the status/hunks widget buffer `mep.sidebar` itself
--- manages) is only hidden for the duration, not touched or replaced
--- — its `bufhidden` is flipped from `'wipe'` (its normal setting,
--- `mep.sidebar.engine`'s own) to `'hide'` first, or swapping it out
--- of `sb.win` would wipe it out from under `sb` right here. A
--- `M.refresh()` firing in the background (e.g. a `mep.git.gutter`
--- change) while composing still re-renders it via the usual
--- `sb:set_sections()`, invisibly, so it's current the moment compose
--- ends. If `sb.win` itself closes mid-compose (`<C-w>c`/`:close`
--- rather than `ZZ`/`ZQ`) — `mep.sidebar.engine`'s own `WinClosed`
--- teardown fires as usual; the `WinClosed` hooked here just forgets
--- this compose's own bookkeeping so a later `open_commit_compose` on
--- the same (recreated) sidebar instance doesn't see a stale "already
--- composing" flag.
local function open_commit_compose(sb)
  if sb._commit_buf or not sb:is_open() then
    return
  end

  local compose_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[compose_buf].buftype = 'nofile'
  vim.bo[compose_buf].bufhidden = 'wipe'
  vim.bo[compose_buf].swapfile = false
  vim.bo[compose_buf].filetype = 'gitcommit'
  vim.api.nvim_buf_set_lines(compose_buf, 0, -1, false, { '' })

  sb._commit_buf = compose_buf
  sb._status_buf = sb.buf
  vim.bo[sb._status_buf].bufhidden = 'hide'

  local status_winbar = vim.wo[sb.win].winbar
  vim.api.nvim_win_set_buf(sb.win, compose_buf)
  vim.wo[sb.win].winbar = '%#MepSidebarTitle# Commit message (ZZ: commit, ZQ: cancel)'
  vim.api.nvim_win_set_cursor(sb.win, { 1, 0 })

  local cleanup_group = vim.api.nvim_create_augroup('MepGitCommitCompose' .. compose_buf, { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = cleanup_group,
    pattern = tostring(sb.win),
    once = true,
    callback = function()
      if sb._commit_buf == compose_buf then
        sb._commit_buf = nil
        sb._status_buf = nil
      end
    end,
  })

  local function finish(do_commit)
    pcall(vim.api.nvim_del_augroup_by_id, cleanup_group)
    local lines = vim.api.nvim_buf_get_lines(compose_buf, 0, -1, false)
    if sb.win and vim.api.nvim_win_is_valid(sb.win) then
      vim.api.nvim_win_set_buf(sb.win, sb._status_buf)
      vim.wo[sb.win].winbar = status_winbar
    end
    vim.bo[sb._status_buf].bufhidden = 'wipe'
    sb._commit_buf = nil
    sb._status_buf = nil

    if not do_commit then
      return
    end
    local message = commit_message_from_lines(lines)
    if message == '' then
      vim.notify('mep.git: empty commit message, aborted', vim.log.levels.WARN)
      return
    end
    status.commit(root(), message, function(ok)
      if ok then
        M.refresh()
      else
        vim.notify('mep.git: commit failed', vim.log.levels.WARN)
      end
    end)
  end

  local map_opts = { buffer = compose_buf, nowait = true, silent = true }
  vim.keymap.set(
    'n',
    'ZZ',
    function()
      finish(true)
    end,
    vim.tbl_extend('force', map_opts, { desc = 'mep.git: commit the message buffer' })
  )
  vim.keymap.set(
    'n',
    'ZQ',
    function()
      finish(false)
    end,
    vim.tbl_extend('force', map_opts, { desc = 'mep.git: discard the message buffer' })
  )
end

--- Bind this library's action keymaps (`mep.git.config.defaults.
--- sidebar.keymaps`: refresh/commit/stage/unstage/discard) to `sb`,
--- buffer-local to whatever buffer it's currently showing. Public so
--- any other `mep.sidebar` instance built on `M.sections()` (`mep.
--- activitybar.git`'s panel, for one) can wire up the same behavior
--- without duplicating it — call this (and `M.refresh()`) from that
--- instance's own `on_open`, the same way `build_opts` does below for
--- `M.dock()`/`M.split()`.
function M.bind_action_keymaps(sb)
  local km = config.options.sidebar.keymaps
  local map_opts = { buffer = sb.buf, nowait = true, silent = true }
  local function map_all(lhs_list, fn, desc)
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, fn, vim.tbl_extend('force', map_opts, { desc = desc }))
    end
  end

  map_all(km.refresh, function()
    M.refresh()
  end, 'mep.git: refresh')

  map_all(km.commit, function()
    open_commit_compose(sb)
  end, 'mep.git: open a commit message buffer (ZZ commits, ZQ cancels)')

  map_all(km.stage, function()
    local kind, path = parse_status_widget(widget_under_cursor(sb))
    if kind == 'unstaged' or kind == 'untracked' then
      status.stage(root(), path, M.refresh)
    end
  end, 'mep.git: stage file under cursor')

  map_all(km.unstage, function()
    local kind, path = parse_status_widget(widget_under_cursor(sb))
    if kind == 'staged' then
      status.unstage(root(), path, M.refresh)
    end
  end, 'mep.git: unstage file under cursor')

  map_all(km.discard, function()
    local kind, path = parse_status_widget(widget_under_cursor(sb))
    if kind ~= 'unstaged' and kind ~= 'untracked' then
      return
    end
    if vim.fn.confirm('Discard changes to ' .. path .. '?', '&Yes\n&No', 2) ~= 1 then
      return
    end
    status.discard(root(), path, kind == 'untracked', M.refresh)
  end, 'mep.git: discard changes under cursor')
end

local function build_opts(extra)
  return vim.tbl_extend('force', {
    title = 'Git',
    position = config.options.sidebar.position,
    width = config.options.sidebar.width,
    height = config.options.sidebar.height,
    border = config.options.sidebar.border,
    animate = config.options.sidebar.animate,
    -- A status panel you glance at, not one that steals the cursor out
    -- of whatever you were editing — switch into it (e.g. `<C-w>w`)
    -- when you actually want to use its keymaps.
    focus = false,
    sections = M.sections(),
    on_open = function(sb)
      M.bind_action_keymaps(sb)
      M.refresh()
    end,
  }, extra)
end

--- Register an externally-built `mep.sidebar` instance (e.g. `mep.
--- activitybar.git`'s own panel) so it redraws alongside `M.dock()`/
--- `M.split()` on `M.refresh()`/a `mep.git.gutter.on_change` firing,
--- and participates in `target_bufnr()`'s "whichever panel is open"
--- lookup. Returns `sb`, so a caller can build-and-register in one
--- expression. Idempotent-ish in practice: only ever called once per
--- instance, from that instance's own lazy constructor.
function M.attach(sb)
  ensure_subscribed()
  instances[#instances + 1] = sb
  return sb
end

--- The docked (floating, edge-anchored) panel instance, building it
--- (closed) the first time it's needed.
function M.dock()
  if not dock_sidebar then
    dock_sidebar = M.attach(sidebar_mod.new(build_opts({ float = true })))
  end
  return dock_sidebar
end

--- The split (real vsplit/split, "pops up as a split in the current
--- buffer") panel instance, building it (closed) the first time it's
--- needed.
function M.split()
  if not split_sidebar then
    split_sidebar = M.attach(sidebar_mod.new(build_opts({ float = false })))
  end
  return split_sidebar
end

--- Toggle the docked panel, closing the split one first if it's open
--- (same content, one presentation at a time).
function M.toggle_dock()
  if split_sidebar and split_sidebar:is_open() then
    split_sidebar:close()
  end
  M.dock():toggle()
end

--- Toggle the split panel, closing the docked one first if it's open.
function M.toggle_split()
  if dock_sidebar and dock_sidebar:is_open() then
    dock_sidebar:close()
  end
  M.split():toggle()
end

--- Test/dev-only: close every registered instance (`M.dock()`/`M.
--- split()`'s own, plus anything `M.attach`ed externally) and forget
--- them, and the `mep.git.gutter.on_change` subscription (call `mep.
--- git.gutter._reset()` too in the same cleanup, or the next `ensure_
--- subscribed()` double-subscribes into its still-live callback list).
--- Does *not* close/forget an externally-attached instance's own
--- owning module's state (e.g. `mep.activitybar.git`'s own `sidebar`
--- local) — that module's own `_reset()` is still responsible for its
--- half.
function M._reset()
  for _, sb in ipairs(instances) do
    pcall(function()
      sb:close()
    end)
  end
  instances = {}
  dock_sidebar = nil
  split_sidebar = nil
  subscribed = false
end

return M

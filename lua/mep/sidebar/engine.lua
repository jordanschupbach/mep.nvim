--- The Sidebar class: owns one persistent window/buffer showing sections
--- of widgets (`mep.sidebar.render` turns those into buffer content).
--- Two window styles, `opts.float`: a real vertical/horizontal split by
--- default (participates in normal window layout, reflows neighboring
--- windows, `mep.filetree`'s single tree panel's own approach), or a
--- floating window flush against the requested edge (`mep.activitybar`'s
--- own choice — a "popup buffer" that neither disturbs nor gets
--- disturbed by other windows). Unlike `mep.filetree`, more than one
--- Sidebar can be open at once (each `Sidebar.new(...)` is its own
--- independent instance, `mep.picker`'s own `Picker.new(...)`/
--- `Picker:method()` object-instance pattern) — `mep.activitybar` needs
--- exactly that: a persistent button bar plus three separate flyout
--- panels, all `mep.sidebar` instances at once.
local render = require('mep.sidebar.render')
local config = require('mep.sidebar.config')

local uv = vim.uv or vim.loop

local Sidebar = {}
Sidebar.__index = Sidebar

local SPLIT_CMD = {
  left = function(size)
    return 'topleft ' .. size .. 'vsplit'
  end,
  right = function(size)
    return 'botright ' .. size .. 'vsplit'
  end,
  top = function(size)
    return 'topleft ' .. size .. 'split'
  end,
  bottom = function(size)
    return 'botright ' .. size .. 'split'
  end,
}

-- Continuously tracks the most recent window that *isn't* one of our
-- own (any window showing a `filetype = 'mep-sidebar'` buffer — every
-- Sidebar's own, set in `_create_window` below, bar and panel alike) —
-- `open()` uses this as `target_win` instead of blindly trusting
-- "whatever's current right now". That distinction matters because a
-- mouse click on a widget (e.g. one of `mep.activitybar`'s own icon
-- buttons) moves real focus into *that* sidebar's window before the
-- resulting `on_click` callback — which may itself open a *different*
-- Sidebar — ever runs; naively capturing "current window" at that point
-- would treat the button bar itself as the thing to return focus to
-- (`opts.focus = false`) or restore focus to on close, instead of
-- wherever the user actually was before touching any sidebar at all.
local last_real_win = nil
local tracking_group = nil
-- `_create_window`'s real-split branch (`opts.float = false`) briefly
-- shows the *old* current buffer in the freshly split window — `:split`
-- duplicates whatever was current, `nvim_win_set_buf` swaps in the
-- sidebar's own scratch buffer only a couple lines later — so a
-- `WinEnter` firing in that gap would see a not-yet-'mep-sidebar'
-- buffer and misidentify the sidebar's own new window as "real".
-- Suspending tracking for the full `_create_window` call sidesteps that
-- race outright rather than trying to out-order it.
local tracking_suspended = false

local function is_sidebar_win(win)
  local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok then
    return false
  end
  return vim.bo[buf].filetype == 'mep-sidebar'
end

local function record_real_win()
  if tracking_suspended then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(win) and not is_sidebar_win(win) then
    last_real_win = win
  end
end

--- Start tracking (idempotent — a second call is a no-op) if not
--- already. Called from `Sidebar.new`, not at `require` time — nothing
--- here should have a side effect just from being required.
local function ensure_tracking()
  if tracking_group then
    return
  end
  tracking_group = vim.api.nvim_create_augroup('MepSidebarFocusTracking', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, {
    group = tracking_group,
    callback = record_real_win,
  })
  record_real_win() -- seed with wherever we already are
end

--- The window `open()` should treat as "where the user actually was"
--- — `last_real_win` if tracking has ever recorded one and it's still
--- valid, else (tracking not started yet, or that window's since
--- closed) whatever's current right now, `open()`'s own previous
--- behavior.
local function resolve_target_win()
  if last_real_win and vim.api.nvim_win_is_valid(last_real_win) then
    return last_real_win
  end
  return vim.api.nvim_get_current_win()
end

--- opts (all optional, falling back to `mep.sidebar.config.defaults`):
--- `title`, `position` ('left'/'right'/'top'/'bottom'), `width`,
--- `height`, `float`, `animate`, `animate_ms`, `animate_steps`,
--- `resize_step`, `min_size`, `border` (floating windows only — see
--- `_float_geometry`), `keymaps`, `sections` (see mep.sidebar.render's
--- header comment for the section/widget shape), `on_open(sidebar)`,
--- `on_close(sidebar)`.
function Sidebar.new(opts)
  opts = opts or {}
  ensure_tracking()
  local resolved = vim.tbl_deep_extend('force', vim.deepcopy(config.options), opts)
  return setmetatable({
    opts = resolved,
    sections = opts.sections or {},
    win = nil,
    buf = nil,
    target_win = nil,
    activatable = {},
    augroup = nil,
    tooltip_win = nil,
    animate_timer = nil,
  }, Sidebar)
end

function Sidebar:is_open()
  return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

local function is_vertical(position)
  return position == 'left' or position == 'right'
end

--- How many screen rows the tabline currently occupies (0 or 1). A
--- floating window's `row = 0` (`relative = 'editor'`) lands on the
--- tabline's own row, not below it the way a real split's first window
--- automatically does (confirmed empirically: `nvim_win_get_position`
--- on a normal window reports row 1 with the tabline shown, but a fresh
--- `row = 0` float reports row 0, right on top of it) — every full-span
--- float below (a left/right sidebar's height, a top sidebar's row)
--- has to account for this itself. Mirrors Neovim's own "is the tabline
--- actually drawn" rule: always at `showtabline = 2`, or at `= 1` only
--- once a second tab exists.
local function tabline_rows()
  if vim.o.showtabline == 2 then
    return 1
  end
  if vim.o.showtabline == 1 and vim.fn.tabpagenr('$') > 1 then
    return 1
  end
  return 0
end

function Sidebar:_target_size()
  return is_vertical(self.opts.position) and self.opts.width or self.opts.height
end

function Sidebar:_current_size()
  if not self:is_open() then
    return 0
  end
  if is_vertical(self.opts.position) then
    return vim.api.nvim_win_get_width(self.win)
  end
  return vim.api.nvim_win_get_height(self.win)
end

--- How many extra columns/rows a floating window's border reserves on
--- every side (0 for no border/`'none'`, else 2 — 1 per side). Exposed
--- on the class table (`Sidebar.border_pad`, a plain function, not a
--- `:method`) so a composite layout like `mep.activitybar`'s bar+panels
--- can compute a correct `edge_offset` for its panels without
--- reimplementing this arithmetic.
local function border_pad(border)
  return (not border or border == 'none') and 0 or 2
end
Sidebar.border_pad = border_pad

--- The `nvim_open_win`/`nvim_win_set_config` geometry for a *floating*
--- sidebar at size `n` (width for left/right, height for top/bottom):
--- `relative = 'editor'`, flush against `opts.position`'s edge, and
--- spanning the *other* dimension in full (the whole editor height for
--- a left/right sidebar, the whole width for top/bottom) — a floating
--- window's `row`/`col` don't auto-adjust the way a real split's
--- neighbors do, so a right/bottom-anchored one has to recompute its
--- own `col`/`row` from `n` every time to stay pinned to that edge as
--- it grows/shrinks (left/top ones stay at `col`/`row = 0` regardless
--- of `n`, so this only actually matters for right/bottom — see
--- `_set_size`, which calls this on every resize/animation step, not
--- just at creation). `opts.edge_offset` (default 0) additionally insets
--- the anchored side by that many columns/rows — how a floating panel
--- stacks *adjacent* to another fixed floating element already sitting
--- on the true screen edge (e.g. `mep.activitybar`'s own icon-button
--- bar) instead of underneath/overlapping it: without this, two
--- independently right-anchored floats both measure their `col` from
--- the real screen edge and collide.
function Sidebar:_float_geometry(n)
  local pad = border_pad(self.opts.border)
  local offset = self.opts.edge_offset or 0
  local top_reserve = tabline_rows()
  if is_vertical(self.opts.position) then
    local height = math.max(1, vim.o.lines - vim.o.cmdheight - pad - top_reserve)
    local col = (self.opts.position == 'right') and math.max(0, vim.o.columns - n - pad - offset) or offset
    return { relative = 'editor', row = top_reserve, col = col, width = n, height = height }
  end
  local width = math.max(1, vim.o.columns - pad)
  local row
  if self.opts.position == 'bottom' then
    row = math.max(0, vim.o.lines - vim.o.cmdheight - n - pad - offset)
  else
    row = top_reserve + offset
  end
  return { relative = 'editor', row = row, col = 0, width = width, height = n }
end

function Sidebar:_set_size(n)
  if not self:is_open() then
    return
  end
  n = math.max(1, n)
  if self.opts.float then
    pcall(vim.api.nvim_win_set_config, self.win, self:_float_geometry(n))
  elseif is_vertical(self.opts.position) then
    vim.api.nvim_win_set_width(self.win, n)
  else
    vim.api.nvim_win_set_height(self.win, n)
  end
end

--- Ramp the current size to `target` over `opts.animate_steps` ticks
--- (`opts.animate_ms` apart), calling `on_done` once it lands exactly
--- on `target`. Cancels any animation already in flight for this
--- instance first — resize/close mid-animation shouldn't fight a
--- previous one.
function Sidebar:_animate_to(target, on_done)
  if self.animate_timer then
    pcall(function()
      self.animate_timer:stop()
      self.animate_timer:close()
    end)
    self.animate_timer = nil
  end

  local start = self:_current_size()
  local steps = math.max(1, self.opts.animate_steps)
  local step_n = 0
  local timer = uv.new_timer()
  self.animate_timer = timer
  timer:start(
    0,
    self.opts.animate_ms,
    vim.schedule_wrap(function()
      step_n = step_n + 1
      if not self:is_open() then
        timer:stop()
        timer:close()
        self.animate_timer = nil
        return
      end
      local size = math.floor(start + (target - start) * (step_n / steps) + 0.5)
      self:_set_size(size)
      if step_n >= steps then
        self:_set_size(target)
        timer:stop()
        timer:close()
        self.animate_timer = nil
        if on_done then
          on_done()
        end
      end
    end)
  )
end

local function apply_common_win_opts(win, title)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  if title then
    vim.wo[win].winbar = '%#MepSidebarTitle# ' .. title
  end
end

function Sidebar:_create_window()
  tracking_suspended = true
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mep-sidebar'

  local initial_size = self.opts.animate and 1 or self:_target_size()
  local win

  if self.opts.float then
    local geometry = self:_float_geometry(initial_size)
    win = vim.api.nvim_open_win(
      buf,
      true,
      vim.tbl_extend('force', geometry, { style = 'minimal', border = self.opts.border, focusable = true })
    )
  else
    vim.cmd(SPLIT_CMD[self.opts.position](initial_size))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    -- A real split's own size is otherwise fair game for Neovim's
    -- 'equalalways' (on by default): opening/closing *any* other
    -- window in the tabpage would silently resize this one too, even
    -- though a persistent sidebar (mep.filetree's own panel, or this
    -- one) is supposed to hold a fixed size regardless of what else is
    -- splitting elsewhere — confirmed the hard way, this is exactly
    -- what made unrelated splits visibly resize the file tree.
    if is_vertical(self.opts.position) then
      vim.wo[win].winfixwidth = true
    else
      vim.wo[win].winfixheight = true
    end
  end

  apply_common_win_opts(win, self.opts.title)
  self.buf, self.win = buf, win
  tracking_suspended = false
end

function Sidebar:_render()
  if not self:is_open() then
    return
  end
  local built = render.build(self.sections)
  self.activatable = built.activatable
  render.write(self.buf, built)
end

--- Replace this sidebar's sections entirely and re-render. Widget/
--- section `on_click`/`tooltip` closures are free to call this on their
--- own sidebar (e.g. "dismiss" removing itself from `self.sections` and
--- redrawing) — see mep.activitybar's notifications/todo panels.
function Sidebar:set_sections(sections)
  self.sections = sections or {}
  self:_render()
end

function Sidebar:_widget_at_cursor()
  if not self:is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(self.win)[1]
  return self.activatable[lnum]
end

--- Toggle (or force, if `collapsed` is given) whether section `id` is
--- collapsed, and re-render.
function Sidebar:collapse_section(id, collapsed)
  local section = render.find_section(self.sections, id)
  if not section then
    return
  end
  if collapsed == nil then
    section.collapsed = not section.collapsed
  else
    section.collapsed = collapsed
  end
  self:_render()
end

--- Run whatever's under the cursor: a section header toggles its own
--- collapse state; a widget with an `on_click` runs it (`on_click(widget,
--- sidebar)`); anything else (a plain info widget, or nothing at all) is
--- a no-op.
function Sidebar:_activate_at_cursor()
  local entry = self:_widget_at_cursor()
  if not entry then
    return
  end
  if entry.kind == 'section' then
    self:collapse_section(entry.section_id)
    return
  end
  local widget = render.find_widget(self.sections, entry.section_id, entry.widget_id)
  if widget and widget.on_click then
    widget.on_click(widget, self)
  end
end

--- Grow (positive `delta`) or shrink (negative) by `delta` columns/rows
--- (default `opts.resize_step`), clamped to `opts.min_size`.
function Sidebar:resize(delta)
  delta = delta or self.opts.resize_step
  self:_set_size(math.max(self.opts.min_size, self:_current_size() + delta))
end

function Sidebar:_close_tooltip()
  if self.tooltip_win and vim.api.nvim_win_is_valid(self.tooltip_win) then
    vim.api.nvim_win_close(self.tooltip_win, true)
  end
  self.tooltip_win = nil
end

function Sidebar:_show_tooltip()
  self:_close_tooltip()
  local entry = self:_widget_at_cursor()
  if not entry or entry.kind ~= 'widget' then
    return
  end
  local widget = render.find_widget(self.sections, entry.section_id, entry.widget_id)
  if not widget or not widget.tooltip then
    return
  end
  local text = widget.tooltip
  if type(text) == 'function' then
    text = text(widget)
  end
  if not text or text == '' then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  self.tooltip_win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = math.max(vim.fn.strdisplaywidth(text), 4),
    height = 1,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  })
end

function Sidebar:_bind_keymaps()
  local map_opts = { buffer = self.buf, nowait = true, silent = true }
  local km = self.opts.keymaps
  local function map_all(lhs_list, fn, desc)
    local opts = vim.tbl_extend('force', map_opts, { desc = desc })
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, fn, opts)
    end
  end

  map_all(km.activate, function()
    self:_activate_at_cursor()
  end, 'mep.sidebar: activate widget/section under cursor')
  map_all(km.close, function()
    self:close()
  end, 'mep.sidebar: close')
  map_all(km.increase_size, function()
    self:resize(self.opts.resize_step)
  end, 'mep.sidebar: increase size')
  map_all(km.decrease_size, function()
    self:resize(-self.opts.resize_step)
  end, 'mep.sidebar: decrease size')

  -- real mouse-click support, not just <CR> — "run functions on click"
  -- literally, not just "on activate"
  vim.keymap.set(
    'n',
    '<LeftRelease>',
    function()
      local pos = vim.fn.getmousepos()
      if pos.winid == self.win then
        pcall(vim.api.nvim_win_set_cursor, self.win, { pos.line, math.max(0, pos.column - 1) })
        self:_activate_at_cursor()
      end
    end,
    vim.tbl_extend('force', map_opts, { desc = 'mep.sidebar: click' })
  )
end

function Sidebar:_bind_autocmds()
  self.augroup = vim.api.nvim_create_augroup('MepSidebar' .. tostring(self.buf), { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = self.augroup,
    pattern = tostring(self.win),
    once = true,
    callback = function()
      self.win = nil
      self.buf = nil
      self:_close_tooltip()
      if self.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
        self.augroup = nil
      end
      -- a floating window doesn't reliably hand focus back the way
      -- closing a real split does — restore it explicitly to wherever
      -- it was when this sidebar opened, when that window still exists.
      if self.target_win and vim.api.nvim_win_is_valid(self.target_win) then
        pcall(vim.api.nvim_set_current_win, self.target_win)
      end
      if self.opts.on_close then
        self.opts.on_close(self)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
    group = self.augroup,
    buffer = self.buf,
    callback = function()
      self:_show_tooltip()
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
    group = self.augroup,
    buffer = self.buf,
    callback = function()
      self:_close_tooltip()
    end,
  })
end

--- Open the sidebar (no-op if already open), sliding into view unless
--- `opts.animate == false`. Leaves focus in the new window unless
--- `opts.focus == false`, in which case it's handed straight back to
--- `target_win` right after rendering — before `on_open`, so that hook
--- still sees (and can further redirect) whichever window actually
--- ends up current.
function Sidebar:open()
  if self:is_open() then
    return
  end
  self.target_win = resolve_target_win()
  self:_create_window()
  self:_bind_keymaps()
  self:_bind_autocmds()
  self:_render()
  if not self.opts.focus and vim.api.nvim_win_is_valid(self.target_win) then
    vim.api.nvim_set_current_win(self.target_win)
  end
  if self.opts.animate then
    self:_animate_to(self:_target_size())
  end
  if self.opts.on_open then
    self.opts.on_open(self)
  end
end

--- Close the sidebar (no-op if not open), sliding out of view first
--- unless `opts.animate == false`. All actual teardown (state, augroup,
--- `on_close`) happens in the `WinClosed` handler `open()` registers, so
--- closing the window through any means (this method, `q`, `<C-w>c`,
--- `:close`) stays consistent.
function Sidebar:close()
  if not self:is_open() then
    return
  end
  local function do_close()
    if self.win and vim.api.nvim_win_is_valid(self.win) then
      vim.api.nvim_win_close(self.win, true)
    end
  end
  if self.opts.animate then
    self:_animate_to(1, do_close)
  else
    do_close()
  end
end

function Sidebar:toggle()
  if self:is_open() then
    self:close()
  else
    self:open()
  end
end

return Sidebar

--- The manual layout: recursive splits (`:vsplit`/`:split`, functionally
--- identical to Neovim's own — this module never reimplements window
--- geometry) where every pane can additionally hold a list of buffer
--- "tabs" with one active, shown via that window's own `winbar` — a
--- Neovim-native primitive Vim itself has no equivalent concept of, so
--- it's emulated here rather than ported from mep-wm's real tree
--- (`~/projects/mep-wm`'s own `Mod+v`/`Mod+s`/`Mod+Tab`/directional
--- keymaps — this module's own `split`/`next_tab`,`prev_tab`/`move`, its
--- own `Alt` equivalents by default).
---
--- State is a plain `{ [winid] = { tabs = {bufnr, ...}, active =
--- index } }` map, not a parallel tree: Neovim's *real* window tree
--- already gets splitting/closing/resizing/directional-focus geometry
--- right (`:vsplit`/`:split`/`:close`, `<C-w>h/j/k/l`, `:resize`) — the
--- only thing actually missing is "which buffers has this specific
--- window shown, and which one's active", so that's the only thing
--- tracked. A window is adopted into this state lazily, the moment any
--- operation here first touches it (`ensure_tracked`) — not eagerly at
--- `enable()` — so a window opened by something else entirely (`:copen`,
--- an LSP peek, `mep.git`'s own panels, ...) is simply never tracked
--- unless you actually split/move-into it.
local config = require('mep.window.config')

local M = {}

local state = {}
local empty_buf = nil
local augroup = nil

--- The shared "empty pane" scratch buffer, creating it the first time
--- it's needed. One instance, reused by every empty pane at once
--- (`bufhidden = 'hide'`, not `'wipe'` — several windows can be showing
--- it simultaneously, and one of them stopping must not delete it out
--- from under the others).
local function ensure_empty_buffer()
  if empty_buf and vim.api.nvim_buf_is_valid(empty_buf) then
    return empty_buf
  end
  empty_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[empty_buf].buftype = 'nofile'
  vim.bo[empty_buf].bufhidden = 'hide'
  vim.bo[empty_buf].swapfile = false
  vim.bo[empty_buf].filetype = 'mep-window-empty'
  return empty_buf
end

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
  return nil
end

--- `bufnr`'s display name for the tab bar: its tail filename (or
--- `[No Name]`), with a trailing `●` while it has unsaved changes.
local function tab_label(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  name = (name == '') and '[No Name]' or vim.fn.fnamemodify(name, ':t')
  if vim.bo[bufnr].modified then
    name = name .. ' ●'
  end
  return name
end

--- Render `win`'s own tab bar into its `winbar` — blank (no bar at
--- all) for an untracked window or one with one tab or fewer, matching
--- mep-wm's own "panes with more than one tab get a clickable tab bar"
--- (this one isn't click-driven — see the module header — but the
--- "don't show it needlessly" half still applies).
local function render_winbar(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local st = state[win]
  if not st or #st.tabs <= 1 then
    pcall(function()
      vim.wo[win].winbar = ''
    end)
    return
  end
  local parts = {}
  for i, bufnr in ipairs(st.tabs) do
    local hl = (i == st.active) and 'MepWindowTabActive' or 'MepWindowTab'
    parts[#parts + 1] = string.format('%%#%s# %s %%*', hl, tab_label(bufnr))
  end
  pcall(function()
    vim.wo[win].winbar = table.concat(parts)
  end)
end

--- Start tracking `win` if it isn't already, seeding its tab list from
--- whatever it's currently showing (empty if that's the shared empty-
--- pane buffer, a single tab otherwise). Idempotent.
local function ensure_tracked(win)
  if state[win] then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if buf == ensure_empty_buffer() then
    state[win] = { tabs = {}, active = 0 }
  else
    state[win] = { tabs = { buf }, active = 1 }
  end
  render_winbar(win)
end

--- `BufWinEnter` handler for a tracked window: append `win`'s
--- newly-shown buffer as a new tab (or, if it's already one of this
--- pane's tabs — e.g. cycling back via `next_tab`/`prev_tab`, or a
--- plain `:buffer N` — just move `active` to it) and re-render its tab
--- bar. A no-op for an untracked window, or the shared empty-pane
--- placeholder (never itself a "tab").
local function sync(win)
  local st = state[win]
  if not st then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if buf == ensure_empty_buffer() then
    return
  end
  local idx = index_of(st.tabs, buf)
  if idx then
    st.active = idx
  else
    st.tabs[#st.tabs + 1] = buf
    st.active = #st.tabs
  end
  render_winbar(win)
end

--- How many real (`mep.window` never tiles/tracks floats — same reason
--- `mep.window.auto` skips them) windows are open in the current
--- tabpage — `collapse_if_empty` (via `remove`/`move`) uses this to
--- decide whether closing a pane down to zero tabs should actually
--- close the window, or (it would be the tabpage's last one) close the
--- tabpage itself instead.
local function real_window_count()
  local n = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == '' then
      n = n + 1
    end
  end
  return n
end

--- Collapse `win`'s pane once its tab list has been emptied (by
--- `remove`/`move`): close the window; if it's the tabpage's last real
--- one, close the whole tabpage instead (`:tabclose`, moving focus to
--- an adjacent tab — same as emptying the last real window of any tab
--- you didn't reach through this module, e.g. `:close` typed directly),
--- unless this is *also* the last tabpage, in which case fall back to
--- the shared empty-pane buffer instead — Neovim never allows closing
--- the very last window across every tab.
local function collapse_if_empty(win)
  if real_window_count() > 1 then
    vim.api.nvim_win_close(win, false)
  elseif vim.fn.tabpagenr('$') > 1 then
    vim.cmd('tabclose')
  else
    if state[win] then
      state[win].active = 0
    end
    vim.api.nvim_win_set_buf(win, ensure_empty_buffer())
    render_winbar(win)
  end
end

--- Split the current pane — `'v'`ertical (side by side, `:vsplit`) or
--- `'h'`orizontal (stacked, `:split`) — loading the shared empty-pane
--- buffer into the new one and selecting it (`:vsplit`/`:split`
--- already leave the new window current), so the next buffer opened
--- there becomes its first tab. Adopts the pane being split if it
--- wasn't already tracked.
function M.split(direction)
  local win = vim.api.nvim_get_current_win()
  ensure_tracked(win)
  -- Predictable, tiling-WM-like placement (new pane to the right/below
  -- the one being split) regardless of the user's own 'splitright'/
  -- 'splitbelow' — confirmed empirically while building this: Neovim's
  -- own *default* (both off) puts a new pane to the left/above instead,
  -- which reads as "split" swapping panes rather than adding one.
  -- 'equalalways' (on by default) is overridden here too, for the same
  -- "predictable, nothing-moves-unexpectedly" reason: with it on,
  -- splitting *any* pane re-equalizes *every* window in the tabpage,
  -- not just the one being split — every other pane visibly resizes
  -- too, undoing whatever sizes `<A-S-h/j/k/l>` set up. Off, a split
  -- only ever divides the pane being split, roughly 50/50, leaving
  -- every other pane's size untouched — confirmed the hard way against
  -- Neovim's own default (on) behavior. 'winwidth'/'winheight' (20/1
  -- by default) are the third: the *new* split becomes the current
  -- window as part of the same command, and Neovim force-grows
  -- whichever window is current to at least that wide/tall, stealing
  -- the difference from a neighbor — confirmed the hard way, this
  -- alone (independent of 'equalalways') was enough to shrink an
  -- unrelated pane on every split. `M.enable()` already sets all three
  -- of these persistently while manual layout is active, making this
  -- local save/restore redundant most of the time — it's still here so
  -- `M.split` gives the same guarantee even if called without
  -- `enable()` (or after a later `disable()`).
  local save_splitright, save_splitbelow, save_equalalways, save_winwidth, save_winheight =
    vim.o.splitright, vim.o.splitbelow, vim.o.equalalways, vim.o.winwidth, vim.o.winheight
  vim.o.splitright = true
  vim.o.splitbelow = true
  vim.o.equalalways = false
  vim.o.winwidth = 1
  vim.o.winheight = 1
  vim.cmd(direction == 'v' and 'vsplit' or 'split')
  vim.o.splitright, vim.o.splitbelow, vim.o.equalalways, vim.o.winwidth, vim.o.winheight =
    save_splitright, save_splitbelow, save_equalalways, save_winwidth, save_winheight

  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, ensure_empty_buffer())
  state[new_win] = { tabs = {}, active = 0 }
  render_winbar(win)
  render_winbar(new_win)
end

local function cycle_tab(delta)
  local win = vim.api.nvim_get_current_win()
  ensure_tracked(win)
  local st = state[win]
  if #st.tabs <= 1 then
    return
  end
  st.active = ((st.active - 1 + delta) % #st.tabs) + 1
  vim.api.nvim_win_set_buf(win, st.tabs[st.active])
  render_winbar(win)
end

--- Cycle the current pane's active tab forward/backward.
function M.next_tab()
  cycle_tab(1)
end
function M.prev_tab()
  cycle_tab(-1)
end

--- Remove the active tab from the current pane — never deletes the
--- buffer itself, just this pane's own reference to it. If tabs remain,
--- switches to the next one; if that was the pane's last tab (or it
--- already had none — e.g. a freshly `split()` pane nothing was ever
--- opened in), collapses the pane (`collapse_if_empty`) — `<A-d>`
--- always closes the pane it's pressed in, not just ones that happen to
--- have a tracked tab already.
function M.remove()
  local win = vim.api.nvim_get_current_win()
  ensure_tracked(win)
  local st = state[win]
  if #st.tabs == 0 then
    collapse_if_empty(win)
    return
  end
  table.remove(st.tabs, st.active)
  if #st.tabs > 0 then
    st.active = math.min(st.active, #st.tabs)
    vim.api.nvim_win_set_buf(win, st.tabs[st.active])
    render_winbar(win)
  else
    collapse_if_empty(win)
  end
end

--- Move the current pane's active tab into the neighboring pane in
--- `direction` (`'h'`/`'j'`/`'k'`/`'l'`, Neovim's own directional
--- window lookup — `:help CTRL-W_h` and friends, already "smart":
--- nearest by screen position, not just tree-adjacent), collapsing the
--- source pane if that was its last tab (`collapse_if_empty`); the
--- moved buffer becomes the target pane's new active tab, and focus
--- follows it there. A no-op with nothing to move, or no neighbor in
--- that direction.
function M.move(direction)
  local win = vim.api.nvim_get_current_win()
  ensure_tracked(win)
  local st = state[win]
  if #st.tabs == 0 then
    return
  end
  local target_winnr = vim.fn.winnr(direction)
  if target_winnr == vim.fn.winnr() then
    return
  end
  local target_win = vim.fn.win_getid(target_winnr)
  ensure_tracked(target_win)

  local bufnr = st.tabs[st.active]
  table.remove(st.tabs, st.active)
  if #st.tabs > 0 then
    st.active = math.min(st.active, #st.tabs)
    vim.api.nvim_win_set_buf(win, st.tabs[st.active])
    render_winbar(win)
  else
    collapse_if_empty(win)
  end

  local tst = state[target_win]
  local idx = index_of(tst.tabs, bufnr)
  if idx then
    tst.active = idx
  else
    tst.tabs[#tst.tabs + 1] = bufnr
    tst.active = #tst.tabs
  end
  vim.api.nvim_set_current_win(target_win)
  vim.api.nvim_win_set_buf(target_win, bufnr)
  render_winbar(target_win)
end

--- Focus the nearest pane in `direction` — Neovim's own built-in
--- `<C-w>h/j/k/l` (`wincmd`) under the hood; works regardless of
--- whether the current window is a tracked pane at all.
local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ''
end

--- The nearest focusable, non-hidden window among `candidates` in
--- `direction` from `from_win`, comparing *centers* rather than
--- requiring the candidate to sit strictly beyond `from_win`'s own edge
--- — confirmed empirically while building this: an edge-anchored `mep.
--- sidebar` float (`float = true` — `mep.activitybar`'s bar/panels,
--- `mep.git.sidebar.toggle_dock()`'s own panel) doesn't reflow/shrink
--- the normal window underneath it the way a real split would, so it
--- typically *overlaps* that window's own last few columns/rows rather
--- than starting past them; an edge-adjacency check would never match
--- it at all.
local function nearest_window(from_win, direction, candidates)
  local from_pos = vim.api.nvim_win_get_position(from_win)
  local from_row = from_pos[1] + vim.api.nvim_win_get_height(from_win) / 2
  local from_col = from_pos[2] + vim.api.nvim_win_get_width(from_win) / 2

  local best, best_dist
  for _, w in ipairs(candidates) do
    if w ~= from_win then
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.focusable ~= false and not cfg.hide then
        local pos = vim.api.nvim_win_get_position(w)
        local row = pos[1] + vim.api.nvim_win_get_height(w) / 2
        local col = pos[2] + vim.api.nvim_win_get_width(w) / 2
        local ok, dist
        if direction == 'l' then
          ok, dist = col > from_col, col - from_col
        elseif direction == 'h' then
          ok, dist = col < from_col, from_col - col
        elseif direction == 'j' then
          ok, dist = row > from_row, row - from_row
        elseif direction == 'k' then
          ok, dist = row < from_row, from_row - row
        end
        if ok and (not best or dist < best_dist) then
          best, best_dist = w, dist
        end
      end
    end
  end
  return best
end

--- Focus the nearest pane in `direction`. Neovim's own directional
--- `<C-w>h/j/k/l` (`wincmd`) only ever considers normal windows — never
--- entering a floating one (e.g. `mep.activitybar`'s bar/panels, `mep.
--- git.sidebar.toggle_dock()`'s own panel — anything built on `mep.
--- sidebar`'s `float = true`), and, confirmed empirically while
--- building this, not even reliably *leaving* one: from a floating
--- window it jumps back to some previous normal window regardless of
--- which direction was asked for, not genuine directional movement. So:
--- from a normal window, try `wincmd` first, falling back to the
--- nearest focusable float in `direction` (`nearest_window`) only if it
--- didn't move (there's no normal-window neighbor that way — e.g.
--- already at the outer edge); from a *floating* window, skip `wincmd`
--- entirely and go straight to the nearest window — float or normal —
--- in `direction`, so `<A-l>`/`<A-h>` can step further into (or back out
--- of) a stack of several floats (`mep.activitybar`'s bar plus an open
--- panel, say) one at a time, not just bounce straight back to whatever
--- normal window was current before.
function M.focus(direction)
  local before = vim.api.nvim_get_current_win()

  if not is_float(before) then
    pcall(vim.cmd, 'wincmd ' .. direction)
    if vim.api.nvim_get_current_win() ~= before then
      return
    end
    local floats = vim.tbl_filter(is_float, vim.api.nvim_tabpage_list_wins(0))
    local target = nearest_window(before, direction, floats)
    if target then
      vim.api.nvim_set_current_win(target)
    end
    return
  end

  local target = nearest_window(before, direction, vim.api.nvim_tabpage_list_wins(0))
  if target then
    vim.api.nvim_set_current_win(target)
  end
end

-- `l`/`j` are each axis's "primary" direction — `h`/`k` don't get an
-- independent priority of their own; each shares its axis's *primary*
-- neighbor check (`l`'s = the right neighbor, `j`'s = the bottom one)
-- and simply takes the opposite sign of whatever that check produces
-- (`invert = true`). Without that pairing, `h` and `l` (independently
-- preferring their own-named neighbor) would both pick "grow" in a
-- pane with neighbors on *both* sides — confirmed the hard way, it's
-- exactly what made them "do the same thing" in a middle pane instead
-- of one growing and the other shrinking. `primary`/`complement` are
-- `winnr()` direction args (`:help winnr()`, the same ones `M.move`
-- already uses to detect "no neighbor that way").
local RESIZE = {
  l = { cmd = 'vertical resize', primary = 'l', complement = 'h', invert = false },
  h = { cmd = 'vertical resize', primary = 'l', complement = 'h', invert = true },
  j = { cmd = 'resize', primary = 'j', complement = 'k', invert = false },
  k = { cmd = 'resize', primary = 'j', complement = 'k', invert = true },
}

--- Resize the current pane by moving the split boundary `step`
--- columns/rows (`mep.window.config.options.manual.resize_step` if
--- omitted) in `direction` (`h`/`j`/`k`/`l`).
---
--- Both `l`/`h` (and separately `j`/`k`) are decided by ONE question —
--- does the pane have a neighbor to its right (below, for `j`/`k`)? —
--- so that pressing either in the same pane always does opposite
--- things, never "both grow" or "both shrink":
---   * a right neighbor exists (the common case: pane is leftmost or
---     in the middle): `l` GROWS the pane by pushing its own right
---     edge further right (shrinking that neighbor); `h` SHRINKS it
---     (retracts the same right edge back left) instead.
---   * no right neighbor (the pane is rightmost) but there IS a left
---     one: the roles flip — `l` SHRINKS (retracts the pane's own
---     *left* edge right, since there's nothing to its right to push
---     into), `h` GROWS (extends that same left edge further left).
--- `j`/`k` mirror this against a bottom neighbor the same way. A no-op
--- with no neighbor on either side of that axis (alone on it).
function M.resize(direction, step)
  local r = RESIZE[direction]
  if not r then
    return
  end
  step = step or config.options.manual.resize_step

  local current = vim.fn.winnr()
  local sign
  if vim.fn.winnr(r.primary) ~= current then
    sign = '+'
  elseif vim.fn.winnr(r.complement) ~= current then
    sign = '-'
  else
    return
  end
  if r.invert then
    sign = (sign == '+') and '-' or '+'
  end
  pcall(vim.cmd, r.cmd .. ' ' .. sign .. step)
end

--- The tab list `{ tabs = {bufnr, ...}, active = index }` for `win`
--- (current window if omitted), or `nil` if it isn't tracked. Returns
--- the live table, not a copy — treat it as read-only.
function M.get(win)
  return state[win or vim.api.nvim_get_current_win()]
end

--- Link the tab-bar highlight groups to sensible built-in defaults
--- (`default = true`: a no-op wherever the colorscheme, or an earlier
--- call, already defined one) — so the tab bar is visible out of the
--- box without requiring the user to define `MepWindowTab`/
--- `MepWindowTabActive` themselves.
local function define_highlights()
  vim.api.nvim_set_hl(0, 'MepWindowTab', { link = 'TabLine', default = true })
  vim.api.nvim_set_hl(0, 'MepWindowTabActive', { link = 'TabLineSel', default = true })
end

local saved_equalalways = nil
local saved_winwidth = nil
local saved_winheight = nil

--- Register the manual-layout keymaps (`mep.window.config.defaults.
--- manual.keymaps`) and the `BufWinEnter`/`WinClosed` autocmds that
--- keep tracked panes' tab lists in sync. Also overrides three global
--- options (all restored by `disable()`) for as long as manual layout
--- is active, none of which have anything to do with *this* module's
--- own splitting/focus code — they're Neovim's own automatic resizing
--- behavior, which fights a hand-controlled layout (`<A-S-h/j/k/l>`)
--- by design:
---   * `'equalalways'` (on by default) — splitting *or closing* any
---     pane silently re-equalizes every other pane's size too,
---     including persistent panels like `mep.filetree`'s own —
---     confirmed the hard way, that's what made opening/closing the
---     tree (itself a real split) visibly resize whatever else was
---     open. `M.split`'s own local save/restore around just its own
---     `:vsplit`/`:split` call is redundant with this while `mep.
---     window.panes` is enabled, but still correct on its own if `M.
---     split` is ever called without `enable()` (or after a later
---     `disable()`).
---   * `'winwidth'`/`'winheight'` (20/1 by default) — force the
---     *current* window to be at least that wide/tall the moment it
---     becomes current, stealing the difference from whichever other
---     window can spare it — confirmed the hard way, this is what made
---     merely focusing a narrower-than-20-column pane (no split/close
---     involved at all) visibly shrink its neighbor. `1` (Neovim's own
---     minimum valid value for both) means "no forced minimum beyond
---     what's already there."
function M.enable()
  M.disable()
  saved_equalalways = vim.o.equalalways
  saved_winwidth = vim.o.winwidth
  saved_winheight = vim.o.winheight
  vim.o.equalalways = false
  vim.o.winwidth = 1
  vim.o.winheight = 1
  define_highlights()
  local km = config.options.manual.keymaps
  local function map(lhs_list, fn, desc, modes)
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set(modes or 'n', lhs, fn, { desc = desc })
    end
  end

  map(km.split_vertical, function()
    M.split('v')
  end, 'mep.window: split pane vertically')
  map(km.split_horizontal, function()
    M.split('h')
  end, 'mep.window: split pane horizontally')

  -- focus/resize/move (unlike split/tab-cycle/remove) also work from
  -- real Terminal-mode ({'t'}, keys otherwise going straight to the
  -- job) — not just Terminal-Normal mode (`<C-\><C-n>`, itself just a
  -- flavor of 'n' that these were already bound in) — so you can jump
  -- panes, resize, or move a tab without leaving terminal input mode
  -- first. Switching the current window (focus/move, into or out of a
  -- terminal buffer) or resizing the current one doesn't depend on
  -- which mode you were logically in when the keymap fired, since
  -- these all drive Neovim's window APIs directly rather than typing
  -- literal keys — confirmed the hard way, no `<C-\><C-n>` escape
  -- needed first.
  map(km.focus_left, function()
    M.focus('h')
  end, 'mep.window: focus pane left', { 'n', 't' })
  map(km.focus_down, function()
    M.focus('j')
  end, 'mep.window: focus pane down', { 'n', 't' })
  map(km.focus_up, function()
    M.focus('k')
  end, 'mep.window: focus pane up', { 'n', 't' })
  map(km.focus_right, function()
    M.focus('l')
  end, 'mep.window: focus pane right', { 'n', 't' })

  map(km.resize_left, function()
    M.resize('h')
  end, 'mep.window: resize pane left', { 'n', 't' })
  map(km.resize_down, function()
    M.resize('j')
  end, 'mep.window: resize pane down', { 'n', 't' })
  map(km.resize_up, function()
    M.resize('k')
  end, 'mep.window: resize pane up', { 'n', 't' })
  map(km.resize_right, function()
    M.resize('l')
  end, 'mep.window: resize pane right', { 'n', 't' })

  map(km.move_left, function()
    M.move('h')
  end, 'mep.window: move active tab to the pane on the left', { 'n', 't' })
  map(km.move_down, function()
    M.move('j')
  end, 'mep.window: move active tab to the pane below', { 'n', 't' })
  map(km.move_up, function()
    M.move('k')
  end, 'mep.window: move active tab to the pane above', { 'n', 't' })
  map(km.move_right, function()
    M.move('l')
  end, 'mep.window: move active tab to the pane on the right', { 'n', 't' })

  map(km.next_tab, M.next_tab, 'mep.window: next tab in pane')
  map(km.prev_tab, M.prev_tab, 'mep.window: previous tab in pane')
  map(km.remove, M.remove, 'mep.window: remove active tab from pane')

  augroup = vim.api.nvim_create_augroup('MepWindow', { clear = true })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = augroup,
    callback = function()
      sync(vim.api.nvim_get_current_win())
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        state[win] = nil
      end
    end,
  })
end

--- Undo `enable()`: unbind the manual-layout keymaps and stop syncing
--- tab lists. Existing tracked state (`M.get`) is left alone — panes
--- already open keep their tab lists, they just stop updating.
function M.disable()
  if saved_equalalways ~= nil then
    vim.o.equalalways = saved_equalalways
    saved_equalalways = nil
  end
  if saved_winwidth ~= nil then
    vim.o.winwidth = saved_winwidth
    saved_winwidth = nil
  end
  if saved_winheight ~= nil then
    vim.o.winheight = saved_winheight
    saved_winheight = nil
  end
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  local km = config.options.manual.keymaps
  for _, list in pairs(km) do
    for _, lhs in ipairs(list) do
      pcall(vim.keymap.del, 'n', lhs)
      -- Only focus/resize/move are ever bound in Terminal-mode too
      -- (see enable()), but deleting a mapping that isn't there is a
      -- harmless no-op, so this doesn't need to track which is which.
      pcall(vim.keymap.del, 't', lhs)
    end
  end
end

--- Test/dev-only: drop all tracked state and the shared empty-pane
--- buffer (as `disable()`, plus this), so a fresh `enable()` starts
--- clean.
function M._reset()
  M.disable()
  state = {}
  if empty_buf and vim.api.nvim_buf_is_valid(empty_buf) then
    pcall(vim.api.nvim_buf_delete, empty_buf, { force = true })
  end
  empty_buf = nil
end

return M

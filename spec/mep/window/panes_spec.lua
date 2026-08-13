-- Everything here is real buffers/windows/autocmds (no subprocess
-- involved anywhere in mep.window), so unlike mep.git's specs nothing
-- needs mocking — see spec/README.md: buffers/windows/autocmds all work
-- fine under nlua, only real subprocesses don't.
local panes = require('mep.window.panes')
local config = require('mep.window.config')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.window.panes', function()
  local saved_config
  local created_bufs

  local function make_buf(name)
    local b = vim.api.nvim_create_buf(true, false)
    created_bufs[#created_bufs + 1] = b
    if name then
      vim.api.nvim_buf_set_name(b, name)
    end
    return b
  end

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    config.setup({ manual = { resize_step = 3 } })
    created_bufs = {}
    panes._reset()
    panes.enable() -- BufWinEnter/WinClosed sync only runs once enabled
    vim.cmd('tabnew')
  end)

  after_each(function()
    panes._reset()
    config.options = saved_config
    pcall(vim.cmd, 'tabclose!')
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  describe('split', function()
    it('creates a new pane to the right (vertical) with the shared empty buffer', function()
      local win1 = vim.api.nvim_get_current_win()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      assert.are_not.equal(win1, win2)
      assert.is_true(vim.api.nvim_win_get_position(win2)[2] > vim.api.nvim_win_get_position(win1)[2])
      assert.are.same({ tabs = {}, active = 0 }, panes.get(win2))
      assert.are.equal('mep-window-empty', vim.bo[vim.api.nvim_win_get_buf(win2)].filetype)
    end)

    it('creates a new pane below (horizontal)', function()
      local win1 = vim.api.nvim_get_current_win()
      panes.split('h')
      local win2 = vim.api.nvim_get_current_win()
      assert.is_true(vim.api.nvim_win_get_position(win2)[1] > vim.api.nvim_win_get_position(win1)[1])
    end)

    it('adopts the pane being split if it was not already tracked', function()
      local win1 = vim.api.nvim_get_current_win()
      assert.is_nil(panes.get(win1))
      panes.split('v')
      local buf1 = vim.api.nvim_win_get_buf(win1)
      assert.are.same({ tabs = { buf1 }, active = 1 }, panes.get(win1))
    end)

    it('splitting one pane does not resize an unrelated, already-open one (equalalways off during the split)', function()
      panes.split('v') -- left | right (current = right)
      vim.cmd('wincmd h') -- back to left
      panes.split('v') -- left | middle (current, new) | right — a 3-pane row
      local right = vim.fn.win_getid(vim.fn.winnr('l'))
      local right_width_before = vim.api.nvim_win_get_width(right)

      -- splitting the (unrelated) current/middle pane must leave the
      -- right pane's width exactly as it was — with 'equalalways' on
      -- (Neovim's default), this split would instead re-equalize every
      -- window in the row, changing the right pane's width too.
      panes.split('v')
      assert.are.equal(right_width_before, vim.api.nvim_win_get_width(right))
    end)

    it('splits the current pane roughly 50/50, not by any other proportion', function()
      local win1 = vim.api.nvim_get_current_win()
      local before = vim.api.nvim_win_get_width(win1)
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local after1, after2 = vim.api.nvim_win_get_width(win1), vim.api.nvim_win_get_width(win2)
      assert.is_true(math.abs(after1 - after2) <= 1) -- off-by-one for odd widths
      assert.is_true(after1 < before)
    end)
  end)

  describe("'equalalways'", function()
    it('enable() turns it off, disable() restores whatever it was before', function()
      panes.disable() -- undo before_each's own enable() first, so setting a custom
      -- "before" value below isn't immediately clobbered by *its* own restore
      local saved = vim.o.equalalways
      vim.o.equalalways = false -- deliberately the *non*-default "before" value: if
      -- disable() restored a hardcoded `true` instead of the actual saved value,
      -- this is what would catch it (restoring the real default, true, wouldn't).
      panes.enable()
      assert.is_false(vim.o.equalalways)
      panes.disable()
      assert.is_false(vim.o.equalalways)
      vim.o.equalalways = saved
    end)

    it('split() also saves/restores it locally, for when called without enable() (or after disable())', function()
      panes.disable()
      local saved = vim.o.equalalways
      vim.o.equalalways = true
      panes.split('v')
      assert.is_true(vim.o.equalalways) -- restored to true, unlike while enable() is active
      vim.o.equalalways = saved
    end)
  end)

  describe("'winwidth'/'winheight'", function()
    it('enable() sets both to 1, disable() restores whatever they were before', function()
      panes.disable() -- undo before_each's own enable() first, so setting a custom
      -- "before" value below isn't immediately clobbered by *its* own restore
      local saved_w, saved_h = vim.o.winwidth, vim.o.winheight
      vim.o.winwidth, vim.o.winheight = 20, 5
      panes.enable()
      assert.are.equal(1, vim.o.winwidth)
      assert.are.equal(1, vim.o.winheight)
      panes.disable()
      assert.are.equal(20, vim.o.winwidth)
      assert.are.equal(5, vim.o.winheight)
      vim.o.winwidth, vim.o.winheight = saved_w, saved_h
    end)

    it('focusing a pane narrower than the default winwidth (20) no longer steals space from its neighbor', function()
      panes.split('v')
      vim.cmd('vertical resize 10') -- current pane now 10 wide, under the default winwidth (20)
      local narrow = vim.api.nvim_get_current_win()
      local wide = vim.fn.win_getid(vim.fn.winnr('h'))
      local wide_width_before = vim.api.nvim_win_get_width(wide)

      vim.api.nvim_set_current_win(wide)
      vim.api.nvim_set_current_win(narrow) -- focus back into the narrow pane — no split/close at all

      assert.are.equal(10, vim.api.nvim_win_get_width(narrow))
      assert.are.equal(wide_width_before, vim.api.nvim_win_get_width(wide))
    end)
  end)

  describe('BufWinEnter sync', function()
    it('adds a newly-shown real buffer as a new tab', function()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-a.lua')
      vim.api.nvim_win_set_buf(win2, buf)
      assert.are.same({ tabs = { buf }, active = 1 }, panes.get(win2))
    end)

    it('does not duplicate a tab already in the pane, just switches active to it', function()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf_a = make_buf('/tmp/mep-window-spec-a.lua')
      local buf_b = make_buf('/tmp/mep-window-spec-b.lua')
      vim.api.nvim_win_set_buf(win2, buf_a)
      vim.api.nvim_win_set_buf(win2, buf_b)
      vim.api.nvim_win_set_buf(win2, buf_a) -- revisit, e.g. plain :buffer
      assert.are.same({ tabs = { buf_a, buf_b }, active = 1 }, panes.get(win2))
    end)

    it('does not register the shared empty buffer itself as a tab', function()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      assert.are.same({}, panes.get(win2).tabs)
    end)

    it('is a no-op for an untracked window', function()
      local win = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-untracked.lua')
      vim.api.nvim_win_set_buf(win, buf)
      assert.is_nil(panes.get(win))
    end)
  end)

  describe('next_tab / prev_tab', function()
    local win, buf_a, buf_b, buf_c

    before_each(function()
      panes.split('v')
      win = vim.api.nvim_get_current_win()
      buf_a = make_buf('/tmp/mep-window-spec-a.lua')
      buf_b = make_buf('/tmp/mep-window-spec-b.lua')
      buf_c = make_buf('/tmp/mep-window-spec-c.lua')
      vim.api.nvim_win_set_buf(win, buf_a)
      vim.api.nvim_win_set_buf(win, buf_b)
      vim.api.nvim_win_set_buf(win, buf_c) -- active = 3 (c)
    end)

    it('next_tab wraps around to the first tab', function()
      panes.next_tab()
      assert.are.equal(1, panes.get(win).active)
      assert.are.equal(buf_a, vim.api.nvim_win_get_buf(win))
    end)

    it('prev_tab moves to the previous tab', function()
      panes.prev_tab()
      assert.are.equal(2, panes.get(win).active)
      assert.are.equal(buf_b, vim.api.nvim_win_get_buf(win))
    end)

    it('is a no-op with one tab or fewer', function()
      local win2 = vim.api.nvim_get_current_win()
      panes.split('v') -- a fresh, empty (0-tab) pane
      assert.has_no.errors(function()
        panes.next_tab()
        panes.prev_tab()
      end)
      _ = win2
    end)
  end)

  describe('winbar', function()
    it('is blank for a pane with one tab or fewer', function()
      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      assert.are.equal('', vim.wo[win].winbar)
      local buf = make_buf('/tmp/mep-window-spec-solo.lua')
      vim.api.nvim_win_set_buf(win, buf)
      assert.are.equal('', vim.wo[win].winbar)
    end)

    it('lists every tab, highlighting the active one, once there are 2+', function()
      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      local buf_a = make_buf('/tmp/mep-window-spec-a.lua')
      local buf_b = make_buf('/tmp/mep-window-spec-b.lua')
      vim.api.nvim_win_set_buf(win, buf_a)
      vim.api.nvim_win_set_buf(win, buf_b)
      local bar = vim.wo[win].winbar
      assert.matches('mep%-window%-spec%-a%.lua', bar)
      assert.matches('mep%-window%-spec%-b%.lua', bar)
      assert.matches('MepWindowTabActive', bar)
      assert.matches('mep%-window%-spec%-b%.lua', bar:match('MepWindowTabActive#(.-)%%%*'))
    end)
  end)

  describe('remove', function()
    it('removes just the active tab when others remain, switching to the next one', function()
      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      local buf_a = make_buf('/tmp/mep-window-spec-a.lua')
      local buf_b = make_buf('/tmp/mep-window-spec-b.lua')
      vim.api.nvim_win_set_buf(win, buf_a)
      vim.api.nvim_win_set_buf(win, buf_b)
      panes.remove()
      assert.are.same({ tabs = { buf_a }, active = 1 }, panes.get(win))
      assert.are.equal(buf_a, vim.api.nvim_win_get_buf(win))
    end)

    it('closes the pane once its last tab is removed, if other real windows remain', function()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-only.lua')
      vim.api.nvim_win_set_buf(win2, buf)
      local before = #vim.api.nvim_tabpage_list_wins(0)
      panes.remove()
      assert.are.equal(before - 1, #vim.api.nvim_tabpage_list_wins(0))
      assert.is_false(vim.api.nvim_win_is_valid(win2))
      assert.is_nil(panes.get(win2))
    end)

    it("closes the tabpage when its last real window is removed, if other tabs remain", function()
      -- before_each's own `tabnew` already means at least 2 tabs exist
      -- during every test in this file, so this is the "normal" case;
      -- the dedicated last-tabpage-in-the-whole-editor case (nothing
      -- left to fall back to but the tab itself) is covered below.
      local win = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-tabclose.lua')
      vim.api.nvim_win_set_buf(win, buf)
      local before_tabs = vim.fn.tabpagenr('$')
      panes.remove()
      assert.are.equal(before_tabs - 1, vim.fn.tabpagenr('$'))
      assert.is_false(vim.api.nvim_win_is_valid(win))
      vim.cmd('tabnew') -- restore the "2 tabs" invariant after_each's own tabclose! expects
    end)

    it("falls back to the shared empty buffer instead of closing the very last tabpage", function()
      -- Collapse every OTHER tab down to just this test's own, so this
      -- genuinely exercises "last real window in the whole editor," not
      -- just "last window in *a* tabpage" (which before_each's own
      -- `tabnew` means is otherwise always true here) — the case above
      -- covers that one.
      vim.cmd('tabonly')
      local win = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-last.lua')
      vim.api.nvim_win_set_buf(win, buf)
      panes.remove()
      assert.are.equal(1, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal(1, vim.fn.tabpagenr('$'))
      assert.are.equal('mep-window-empty', vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
      assert.are.same({ tabs = {}, active = 0 }, panes.get(win))
      vim.cmd('tabnew') -- restore the "2 tabs" invariant after_each's own tabclose! expects
    end)

    it('closes a pane with no tabs (e.g. a freshly split, never-populated one), if other real windows remain', function()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local before = #vim.api.nvim_tabpage_list_wins(0)
      panes.remove()
      assert.are.equal(before - 1, #vim.api.nvim_tabpage_list_wins(0))
      assert.is_false(vim.api.nvim_win_is_valid(win2))
      assert.is_nil(panes.get(win2))
    end)
  end)

  describe('move', function()
    it("moves the active tab into the neighboring pane, focus following it", function()
      local win1 = vim.api.nvim_get_current_win()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-move.lua')
      vim.api.nvim_win_set_buf(win2, buf)

      panes.move('h')

      assert.are.equal(win1, vim.api.nvim_get_current_win())
      assert.are.equal(buf, vim.api.nvim_win_get_buf(win1))
      local win1_tabs = panes.get(win1).tabs
      assert.is_not_nil(vim.tbl_contains(win1_tabs, buf))
    end)

    it('collapses the source pane if that was its only tab', function()
      vim.api.nvim_get_current_win()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-move2.lua')
      vim.api.nvim_win_set_buf(win2, buf)

      panes.move('h')

      assert.is_false(vim.api.nvim_win_is_valid(win2))
    end)

    it('is a no-op with no neighbor in that direction', function()
      local win1 = vim.api.nvim_get_current_win()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-edge.lua')
      vim.api.nvim_win_set_buf(win2, buf)

      panes.move('l') -- win2 is already the rightmost pane

      assert.are.equal(win2, vim.api.nvim_get_current_win())
      assert.are.same({ tabs = { buf }, active = 1 }, panes.get(win2))
      _ = win1
    end)

    it('is a no-op on a pane with no tabs', function()
      panes.split('v')
      panes.split('v')
      assert.has_no.errors(function()
        panes.move('h')
      end)
    end)

    it('does not duplicate a buffer already open in the target pane', function()
      local win1 = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-shared.lua')
      vim.api.nvim_win_set_buf(win1, buf)
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win2, buf) -- same buffer, now also a tab in win2

      panes.move('h')

      assert.are.same({ tabs = { buf }, active = 1 }, panes.get(win1))
    end)
  end)

  describe('focus / resize', function()
    it('focus moves to the neighboring window via native wincmd', function()
      local win1 = vim.api.nvim_get_current_win()
      panes.split('v')
      local win2 = vim.api.nvim_get_current_win()
      panes.focus('h')
      assert.are.equal(win1, vim.api.nvim_get_current_win())
      _ = win2
    end)

    -- `resize(direction, step)` always pushes the split boundary in
    -- `direction`'s own screen sense (h=left, j=down, k=up, l=right) —
    -- whether that grows or shrinks the current pane depends on which
    -- side its only neighbor is actually on, not on the key itself.
    -- `panes.split('v')`/`split('h')` (splitright/splitbelow forced
    -- true) always leave the *new* pane rightmost/bottommost — i.e.
    -- exactly the "only a left/top neighbor" case these specs pin down.
    it('in the rightmost pane, l (push right) shrinks — no room to its right, so its own left neighbor grows into it', function()
      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('l', 3)
      assert.are.equal(before_w - 3, vim.api.nvim_win_get_width(win))
    end)

    it('in the rightmost pane, h (push left) grows — its own left edge extends into its left neighbor', function()
      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('h', 3)
      assert.are.equal(before_w + 3, vim.api.nvim_win_get_width(win))
    end)

    it('in the leftmost pane, l (push right) grows — its own right edge extends into its right neighbor', function()
      panes.split('v')
      vim.cmd('wincmd h') -- back to the original (now leftmost) pane
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('l', 3)
      assert.are.equal(before_w + 3, vim.api.nvim_win_get_width(win))
    end)

    it('in the leftmost pane, h (push left) shrinks — no room to its left, so its right neighbor grows into it', function()
      panes.split('v')
      vim.cmd('wincmd h')
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('h', 3)
      assert.are.equal(before_w - 3, vim.api.nvim_win_get_width(win))
    end)

    it('in the bottommost pane, j (push down) shrinks, k (push up) grows', function()
      panes.split('h')
      local win = vim.api.nvim_get_current_win()
      local before_h = vim.api.nvim_win_get_height(win)
      panes.resize('j', 2)
      assert.are.equal(before_h - 2, vim.api.nvim_win_get_height(win))
      panes.resize('k', 2)
      assert.are.equal(before_h, vim.api.nvim_win_get_height(win))
      panes.resize('k', 2)
      assert.are.equal(before_h + 2, vim.api.nvim_win_get_height(win))
    end)

    it('in a vertically-middle pane (neighbors above and below), j grows and k shrinks — never the same thing', function()
      panes.split('h') -- top | bottom, current = bottom
      vim.cmd('wincmd k') -- back to top
      panes.split('h') -- top | middle (current, new) | bottom
      local win = vim.api.nvim_get_current_win()
      local before_h = vim.api.nvim_win_get_height(win)
      panes.resize('j', 2)
      assert.are.equal(before_h + 2, vim.api.nvim_win_get_height(win))
      panes.resize('k', 2)
      assert.are.equal(before_h, vim.api.nvim_win_get_height(win))
      panes.resize('k', 2)
      assert.are.equal(before_h - 2, vim.api.nvim_win_get_height(win))
    end)

    it('in a middle pane (neighbors on both sides), l grows and h shrinks — never the same thing', function()
      panes.split('v') -- left | right, current = right
      vim.cmd('wincmd h') -- back to left
      panes.split('v') -- left | middle (current, new) | right
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('l', 3)
      assert.are.equal(before_w + 3, vim.api.nvim_win_get_width(win))
      panes.resize('h', 3)
      assert.are.equal(before_w, vim.api.nvim_win_get_width(win))
      panes.resize('h', 3)
      assert.are.equal(before_w - 3, vim.api.nvim_win_get_width(win))
    end)

    it('is a no-op with no neighbor on either side of that axis (a lone pane)', function()
      local win = vim.api.nvim_get_current_win()
      local before_w = vim.api.nvim_win_get_width(win)
      panes.resize('l', 3)
      assert.are.equal(before_w, vim.api.nvim_win_get_width(win))
      panes.resize('h', 3)
      assert.are.equal(before_w, vim.api.nvim_win_get_width(win))
    end)

    it('is a harmless no-op for an unknown direction', function()
      assert.has_no.errors(function()
        panes.resize('x')
      end)
    end)
  end)

  -- Neovim's own directional wincmd never enters a floating window (and,
  -- confirmed empirically while building this, isn't even reliably
  -- directional *leaving* one — it jumps back to some previous normal
  -- window regardless of h/j/k/l) — mep.sidebar's own float=true panels
  -- (mep.activitybar's bar/panels, mep.git.sidebar's dock) are exactly
  -- that, so `focus` falls back to its own geometry-based lookup for
  -- them. Built directly on mep.sidebar here rather than mep.activitybar,
  -- to keep this focused on the general float-navigation behavior.
  describe('focus (floating windows)', function()
    local sidebar_mod = require('mep.sidebar')
    local floats

    before_each(function()
      floats = {}
    end)

    after_each(function()
      for _, sb in ipairs(floats) do
        pcall(function()
          sb.opts.animate = false
          sb:close()
        end)
      end
    end)

    local function new_float(opts)
      opts = vim.tbl_extend('force', { float = true, animate = false, focus = false, sections = {} }, opts or {})
      local sb = sidebar_mod.new(opts)
      floats[#floats + 1] = sb
      sb:open()
      return sb
    end

    it('<A-l> enters a right-anchored float when there is no further normal window', function()
      local win1 = vim.api.nvim_get_current_win()
      local sb = new_float({ position = 'right', width = 10 })
      panes.focus('l')
      assert.are.equal(sb.win, vim.api.nvim_get_current_win())
      _ = win1
    end)

    it('<A-h> from inside that float returns to the normal window', function()
      local win1 = vim.api.nvim_get_current_win()
      local sb = new_float({ position = 'right', width = 10 })
      vim.api.nvim_set_current_win(sb.win)
      panes.focus('h')
      assert.are.equal(win1, vim.api.nvim_get_current_win())
    end)

    it('steps through two stacked floats one at a time, nearest first', function()
      local win1 = vim.api.nvim_get_current_win()
      -- edge_offset insets a float *away* from the true screen edge —
      -- so, like mep.activitybar's own bar (edge_offset=0, flush
      -- against the true edge) plus a panel (a positive edge_offset,
      -- stacked between the bar and the normal window), `near` (offset
      -- > 0) sits closer to the normal window than `far` (offset = 0,
      -- flush against the true edge) does.
      local near = new_float({ position = 'right', width = 10, edge_offset = 20 })
      local far = new_float({ position = 'right', width = 10, edge_offset = 0 })

      panes.focus('l')
      assert.are.equal(near.win, vim.api.nvim_get_current_win())
      panes.focus('l')
      assert.are.equal(far.win, vim.api.nvim_get_current_win())
      panes.focus('l') -- nothing further right: stays put
      assert.are.equal(far.win, vim.api.nvim_get_current_win())

      panes.focus('h')
      assert.are.equal(near.win, vim.api.nvim_get_current_win())
      panes.focus('h')
      assert.are.equal(win1, vim.api.nvim_get_current_win())
    end)

    it('does not consider a non-focusable float', function()
      local win1 = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_create_buf(false, true)
      created_bufs[#created_bufs + 1] = buf
      local float = vim.api.nvim_open_win(
        buf,
        false,
        { relative = 'editor', row = 0, col = 79, width = 1, height = 1, focusable = false }
      )
      panes.focus('l')
      assert.are.equal(win1, vim.api.nvim_get_current_win())
      pcall(vim.api.nvim_win_close, float, true)
    end)
  end)

  describe('enable / disable', function()
    after_each(function()
      panes.disable()
    end)

    it('binds the configured keymaps', function()
      config.setup({ manual = { keymaps = { split_vertical = { '<F6>' } } } })
      panes.enable()
      local maps = vim.api.nvim_get_keymap('n')
      local found = false
      for _, m in ipairs(maps) do
        if m.lhs == '<F6>' then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('disable removes the keymaps and stops syncing new tabs', function()
      config.setup({ manual = { keymaps = { remove = { '<F7>' } } } })
      panes.enable()
      panes.disable()
      local maps = vim.api.nvim_get_keymap('n')
      for _, m in ipairs(maps) do
        assert.are_not.equal('<F7>', m.lhs)
      end

      panes.split('v')
      local win = vim.api.nvim_get_current_win()
      local buf = make_buf('/tmp/mep-window-spec-disabled.lua')
      vim.api.nvim_win_set_buf(win, buf)
      -- split() itself still tracks explicitly; disable() only turns off
      -- the *autocmd*-driven sync, so a later plain buffer switch is the
      -- thing that should no longer register.
      local before = vim.deepcopy(panes.get(win))
      local buf2 = make_buf('/tmp/mep-window-spec-disabled-2.lua')
      vim.api.nvim_win_set_buf(win, buf2)
      assert.are.same(before, panes.get(win))
    end)

    it('a real ]<F6>-bound split keymap actually invokes split()', function()
      config.setup({ manual = { keymaps = { split_vertical = { '<F6>' } } } })
      panes.enable()
      local win1 = vim.api.nvim_get_current_win()
      feed('<F6>')
      assert.are_not.equal(win1, vim.api.nvim_get_current_win())
    end)

    local function has_map(mode, lhs)
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.lhs == lhs then
          return true
        end
      end
      return false
    end

    it('binds focus/resize/move in both Normal and Terminal mode', function()
      config.setup({
        manual = {
          keymaps = {
            focus_left = { '<F6>' },
            resize_right = { '<F7>' },
            move_up = { '<F8>' },
          },
        },
      })
      panes.enable()
      for _, lhs in ipairs({ '<F6>', '<F7>', '<F8>' }) do
        assert.is_true(has_map('n', lhs))
        assert.is_true(has_map('t', lhs))
      end
    end)

    it('does not bind split/tab-cycle/remove in Terminal mode', function()
      config.setup({
        manual = {
          keymaps = {
            split_vertical = { '<F6>' },
            next_tab = { '<F7>' },
            remove = { '<F8>' },
          },
        },
      })
      panes.enable()
      for _, lhs in ipairs({ '<F6>', '<F7>', '<F8>' }) do
        assert.is_true(has_map('n', lhs))
        assert.is_false(has_map('t', lhs))
      end
    end)

    it('disable() removes the Terminal-mode focus/resize/move bindings too', function()
      config.setup({ manual = { keymaps = { focus_left = { '<F6>' } } } })
      panes.enable()
      assert.is_true(has_map('t', '<F6>'))
      panes.disable()
      assert.is_false(has_map('t', '<F6>'))
    end)
  end)

  describe('get', function()
    it('returns nil for an untracked window', function()
      assert.is_nil(panes.get(vim.api.nvim_get_current_win()))
    end)
  end)
end)

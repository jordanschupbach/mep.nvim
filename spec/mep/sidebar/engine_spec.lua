local sidebar = require('mep.sidebar.sidebar')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.sidebar.engine', function()
  local created

  before_each(function()
    created = {}
  end)

  after_each(function()
    for _, s in ipairs(created) do
      pcall(function()
        s.opts.animate = false
        s:close()
      end)
    end
  end)

  local function new(opts)
    opts = opts or {}
    if opts.animate == nil then
      opts.animate = false -- deterministic by default; animation gets its own tests
    end
    local s = sidebar.new(opts)
    created[#created + 1] = s
    return s
  end

  describe('open / close / toggle', function()
    it('is not open until open() is called', function()
      local s = new({})
      assert.is_false(s:is_open())
    end)

    it('open() creates a real window sized to opts.width for a vertical sidebar', function()
      local s = new({ position = 'right', width = 22 })
      s:open()
      assert.is_true(s:is_open())
      assert.are.equal(22, vim.api.nvim_win_get_width(s.win))
    end)

    it('open() sizes a horizontal sidebar by opts.height', function()
      local s = new({ position = 'bottom', height = 9 })
      s:open()
      assert.are.equal(9, vim.api.nvim_win_get_height(s.win))
    end)

    it('a real vertical (left/right) sidebar sets winfixwidth, surviving an unrelated split/close', function()
      local s = new({ position = 'right', width = 22 })
      s:open()
      assert.is_true(vim.wo[s.win].winfixwidth)

      vim.cmd('vsplit')
      assert.are.equal(22, vim.api.nvim_win_get_width(s.win))
      vim.cmd('close')
      assert.are.equal(22, vim.api.nvim_win_get_width(s.win))
    end)

    it('a real horizontal (top/bottom) sidebar sets winfixheight, surviving an unrelated split/close', function()
      local s = new({ position = 'bottom', height = 9 })
      s:open()
      assert.is_true(vim.wo[s.win].winfixheight)

      vim.cmd('split')
      assert.are.equal(9, vim.api.nvim_win_get_height(s.win))
      vim.cmd('close')
      assert.are.equal(9, vim.api.nvim_win_get_height(s.win))
    end)

    it('a floating sidebar has neither winfixwidth nor winfixheight set (not part of the split layout)', function()
      local s = new({ position = 'right', width = 22, float = true })
      s:open()
      assert.is_false(vim.wo[s.win].winfixwidth)
      assert.is_false(vim.wo[s.win].winfixheight)
    end)

    it('open() is a no-op when already open', function()
      local s = new({})
      s:open()
      local win = s.win
      s:open()
      assert.are.equal(win, s.win)
    end)

    it('close() tears the window down and is a no-op when not open', function()
      local s = new({})
      s:open()
      local win = s.win
      s:close()
      assert.is_false(s:is_open())
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.has_no.errors(function()
        s:close()
      end)
    end)

    it('toggle() opens then closes', function()
      local s = new({})
      s:toggle()
      assert.is_true(s:is_open())
      s:toggle()
      assert.is_false(s:is_open())
    end)

    it('cleans up state when the window is closed by any means, not just :close()', function()
      local s = new({})
      s:open()
      local win = s.win
      local closed_called = false
      s.opts.on_close = function()
        closed_called = true
      end
      vim.api.nvim_win_close(win, true)
      assert.is_false(s:is_open())
      assert.is_nil(s.buf)
      assert.is_true(closed_called)
    end)

    it('supports more than one sidebar open at once', function()
      local a = new({ position = 'left' })
      local b = new({ position = 'right' })
      a:open()
      b:open()
      assert.is_true(a:is_open())
      assert.is_true(b:is_open())
      assert.are_not.equal(a.win, b.win)
    end)

    it('sets a winbar from opts.title', function()
      local s = new({ title = 'Notifications' })
      s:open()
      assert.matches('Notifications', vim.wo[s.win].winbar)
    end)

    it('restores focus to whatever window was current before opening', function()
      local before = vim.api.nvim_get_current_win()
      local s = new({})
      s:open()
      assert.are_not.equal(before, vim.api.nvim_get_current_win())
      s:close()
      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)

    it('opts.focus = false leaves focus in the original window on open', function()
      local before = vim.api.nvim_get_current_win()
      local s = new({ focus = false })
      s:open()
      assert.are.equal(before, vim.api.nvim_get_current_win())
      assert.is_true(s:is_open())
    end)

    it('opts.focus = false still lets on_open see the window open()d', function()
      local seen_win
      local s = new({
        focus = false,
        on_open = function(sidebar)
          seen_win = sidebar.win
        end,
      })
      s:open()
      assert.are.equal(s.win, seen_win)
    end)
  end)

  -- Reproduces the exact bug scenario mep.activitybar hits: clicking a
  -- widget in one Sidebar (its own window, briefly current the moment
  -- the click fires) opens a *different* Sidebar — naively capturing
  -- "current window" as that second Sidebar's target_win would treat
  -- the first sidebar as "where the user really was" instead of the
  -- actual real window underneath both of them.
  describe('target_win resolution (clicked through another sidebar)', function()
    it('open() resolves target_win to the last real window, not a sidebar it was opened from', function()
      vim.cmd('new') -- a fresh, genuinely "real" window
      local real_win = vim.api.nvim_get_current_win()

      local a = new({ float = true }) -- default focus = true: entering it is real
      a:open()
      assert.are.equal(a.win, vim.api.nvim_get_current_win())

      -- as if `a`'s own on_click opened `b` while `a` itself was current
      local b = new({ float = true, focus = false })
      b:open()
      assert.are.equal(real_win, b.target_win)

      pcall(vim.api.nvim_win_close, real_win, true)
    end)

    it('close() restores focus to the real window, not the sidebar b was opened through', function()
      vim.cmd('new')
      local real_win = vim.api.nvim_get_current_win()

      local a = new({ float = true })
      a:open()
      local b = new({ float = true, focus = false })
      b:open()
      vim.api.nvim_set_current_win(b.win) -- user switches into b to interact with it
      b:close()

      assert.are.equal(real_win, vim.api.nvim_get_current_win())
      pcall(vim.api.nvim_win_close, real_win, true)
    end)

    it('a real split sidebar does not get mistaken for "real" mid-construction', function()
      vim.cmd('new')
      local real_win = vim.api.nvim_get_current_win()

      -- opts.float = false: this briefly duplicates the current buffer
      -- into the new split window before swapping in its own scratch
      -- buffer — the exact race `tracking_suspended` guards against.
      local a = new({ float = false, position = 'right', width = 20 })
      a:open()

      local b = new({ float = true, focus = false })
      b:open()
      assert.are.equal(real_win, b.target_win)

      pcall(vim.api.nvim_win_close, real_win, true)
    end)
  end)

  describe('float', function()
    it('opts.float = true opens a floating window, not a real split', function()
      local s = new({ float = true, position = 'right', width = 22 })
      s:open()
      assert.are_not.equal('', vim.api.nvim_win_get_config(s.win).relative)
    end)

    it('a right-anchored float is flush against the right edge, spanning the full height', function()
      local s = new({ float = true, position = 'right', width = 22, border = 'rounded' })
      s:open()
      local cfg = vim.api.nvim_win_get_config(s.win)
      assert.are.equal(22, cfg.width)
      assert.are.equal(vim.o.columns - 22 - 2, cfg.col) -- 2 cols border padding
      assert.are.equal(0, cfg.row)
      assert.are.equal(vim.o.lines - vim.o.cmdheight - 2, cfg.height)
    end)

    it('a left-anchored float sits flush at column 0', function()
      local s = new({ float = true, position = 'left', width = 22 })
      s:open()
      assert.are.equal(0, vim.api.nvim_win_get_config(s.win).col)
    end)

    it('a bottom-anchored float is flush against the bottom edge, spanning the full width', function()
      local s = new({ float = true, position = 'bottom', height = 8, border = 'rounded' })
      s:open()
      local cfg = vim.api.nvim_win_get_config(s.win)
      assert.are.equal(8, cfg.height)
      assert.are.equal(vim.o.lines - vim.o.cmdheight - 8 - 2, cfg.row)
      assert.are.equal(0, cfg.col)
      assert.are.equal(vim.o.columns - 2, cfg.width)
    end)

    it('border = "none" removes the padding a right-anchored float otherwise reserves', function()
      local s = new({ float = true, position = 'right', width = 22, border = 'none' })
      s:open()
      local cfg = vim.api.nvim_win_get_config(s.win)
      assert.are.equal(vim.o.columns - 22, cfg.col)
      assert.are.equal(vim.o.lines - vim.o.cmdheight, cfg.height)
    end)

    it('resize keeps a right-anchored float pinned to the edge as it grows', function()
      local s = new({ float = true, position = 'right', width = 20, border = 'rounded' })
      s:open()
      s:resize(10)
      local cfg = vim.api.nvim_win_get_config(s.win)
      assert.are.equal(30, cfg.width)
      assert.are.equal(vim.o.columns - 30 - 2, cfg.col)
    end)

    it('does not disturb other real windows the way a split would', function()
      local other = vim.api.nvim_get_current_win()
      local before_width = vim.api.nvim_win_get_width(other)
      local s = new({ float = true, position = 'right', width = 30 })
      s:open()
      assert.are.equal(before_width, vim.api.nvim_win_get_width(other))
    end)

    describe('edge_offset', function()
      it('stacks a right-anchored panel to the left of a fixed edge_offset amount', function()
        local bar = new({ float = true, position = 'right', width = 4, border = 'none' })
        bar:open()
        local panel = new({ float = true, position = 'right', width = 40, border = 'rounded', edge_offset = 4 })
        panel:open()

        local bar_cfg = vim.api.nvim_win_get_config(bar.win)
        local panel_cfg = vim.api.nvim_win_get_config(panel.win)
        -- the panel's own right edge (content + border) must land
        -- exactly at the bar's left edge, no overlap and no gap
        local panel_right_edge = panel_cfg.col + panel_cfg.width + 2
        assert.are.equal(bar_cfg.col, panel_right_edge)
      end)

      it('offsets a left-anchored panel to the right instead', function()
        local s = new({ float = true, position = 'left', width = 20, edge_offset = 5 })
        s:open()
        assert.are.equal(5, vim.api.nvim_win_get_config(s.win).col)
      end)

      it('defaults to 0 (flush against the true screen edge)', function()
        local s = new({ float = true, position = 'right', width = 20, border = 'none' })
        s:open()
        assert.are.equal(vim.o.columns - 20, vim.api.nvim_win_get_config(s.win).col)
      end)
    end)

    describe('tabline reservation', function()
      local saved_showtabline

      before_each(function()
        saved_showtabline = vim.o.showtabline
        vim.o.showtabline = 2 -- always shown, regardless of tab count
      end)

      after_each(function()
        vim.o.showtabline = saved_showtabline
      end)

      it('drops a left/right float below row 0 and shrinks its height to match', function()
        local s = new({ float = true, position = 'right', width = 22, border = 'none' })
        s:open()
        local cfg = vim.api.nvim_win_get_config(s.win)
        assert.are.equal(1, cfg.row)
        assert.are.equal(vim.o.lines - vim.o.cmdheight - 1, cfg.height)
      end)

      it('drops a top float below row 0 instead of covering the tabline', function()
        local s = new({ float = true, position = 'top', height = 10, border = 'none' })
        s:open()
        assert.are.equal(1, vim.api.nvim_win_get_config(s.win).row)
      end)

      it('does not affect a bottom float, which never reaches row 0', function()
        local s = new({ float = true, position = 'bottom', height = 8, border = 'none' })
        s:open()
        assert.are.equal(vim.o.lines - vim.o.cmdheight - 8, vim.api.nvim_win_get_config(s.win).row)
      end)

      it('leaves geometry untouched when the tabline is not shown', function()
        vim.o.showtabline = 0
        local s = new({ float = true, position = 'right', width = 22, border = 'none' })
        s:open()
        assert.are.equal(0, vim.api.nvim_win_get_config(s.win).row)
      end)
    end)
  end)

  describe('rendering', function()
    it('renders configured sections into the buffer', function()
      local s = new({
        sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'hello' } } } },
      })
      s:open()
      assert.are.same({ '▾ A', '  hello' }, vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
    end)

    it('set_sections replaces content and re-renders', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = {} } } })
      s:open()
      s:set_sections({ { id = 'b', title = 'B', widgets = {} } })
      assert.are.same({ '▾ B' }, vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
    end)
  end)

  describe('activation', function()
    it('<CR> on a widget line runs its on_click with (widget, sidebar)', function()
      local seen_widget, seen_sidebar
      local s = new({
        sections = {
          { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'go', on_click = function(w, sb)
            seen_widget, seen_sidebar = w, sb
          end } } },
        },
      })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      feed('<CR>')
      assert.are.equal('w1', seen_widget.id)
      assert.are.equal(s, seen_sidebar)
    end)

    it('<CR> on a widget with no on_click is a harmless no-op', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } } } })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      assert.has_no.errors(function()
        feed('<CR>')
      end)
    end)

    it('<CR> on a section header toggles its collapsed state', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } } } })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 1, 0 })
      feed('<CR>')
      assert.are.same({ '▸ A' }, vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
      feed('<CR>')
      assert.are.same({ '▾ A', '  x' }, vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
    end)

    it('collapse_section can force a specific state', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = {} } } })
      s:open()
      s:collapse_section('a', true)
      assert.is_true(require('mep.sidebar.render').find_section(s.sections, 'a').collapsed)
      s:collapse_section('a', true) -- forcing the same state again stays collapsed
      assert.is_true(require('mep.sidebar.render').find_section(s.sections, 'a').collapsed)
    end)

    it('mouse click (<LeftRelease>) on a widget line runs its on_click', function()
      local ran = false
      local s = new({
        sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'go', on_click = function()
          ran = true
        end } } } },
      })
      s:open()
      local orig = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = s.win, line = 2, column = 3 }
      end
      feed('<LeftRelease>')
      vim.fn.getmousepos = orig
      assert.is_true(ran)
    end)

    it('a click reported for a different window is ignored', function()
      local ran = false
      local s = new({
        sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'go', on_click = function()
          ran = true
        end } } } },
      })
      s:open()
      local orig = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = 999999, line = 2, column = 3 }
      end
      feed('<LeftRelease>')
      vim.fn.getmousepos = orig
      assert.is_false(ran)
    end)
  end)

  describe('border_pad', function()
    it('is 0 for no border / "none"', function()
      assert.are.equal(0, sidebar.border_pad(nil))
      assert.are.equal(0, sidebar.border_pad('none'))
    end)

    it('is 2 for any real border style', function()
      assert.are.equal(2, sidebar.border_pad('rounded'))
      assert.are.equal(2, sidebar.border_pad('single'))
    end)
  end)

  describe('resize', function()
    it('resize(delta) grows/shrinks the window', function()
      local s = new({ position = 'right', width = 20 })
      s:open()
      s:resize(5)
      assert.are.equal(25, vim.api.nvim_win_get_width(s.win))
      s:resize(-10)
      assert.are.equal(15, vim.api.nvim_win_get_width(s.win))
    end)

    it('resize defaults to opts.resize_step', function()
      local s = new({ position = 'right', width = 20, resize_step = 3 })
      s:open()
      s:resize()
      assert.are.equal(23, vim.api.nvim_win_get_width(s.win))
    end)

    it('resize does not shrink below min_size', function()
      local s = new({ position = 'right', width = 10, min_size = 8 })
      s:open()
      s:resize(-50)
      assert.are.equal(8, vim.api.nvim_win_get_width(s.win))
    end)

    it('the increase_size/decrease_size keymaps resize the window', function()
      local s = new({ position = 'right', width = 20, resize_step = 4 })
      s:open()
      feed('+')
      assert.are.equal(24, vim.api.nvim_win_get_width(s.win))
      feed('-')
      feed('-')
      assert.are.equal(16, vim.api.nvim_win_get_width(s.win))
    end)
  end)

  describe('tooltip', function()
    it('_show_tooltip opens a floating window with the widget tooltip text', function()
      local s = new({
        sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x', tooltip = 'helpful hint' } } } },
      })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      s:_show_tooltip()
      assert.is_not_nil(s.tooltip_win)
      assert.is_true(vim.api.nvim_win_is_valid(s.tooltip_win))
      local tbuf = vim.api.nvim_win_get_buf(s.tooltip_win)
      assert.are.same({ 'helpful hint' }, vim.api.nvim_buf_get_lines(tbuf, 0, -1, false))
    end)

    it('supports a function tooltip, called with the widget', function()
      local s = new({
        sections = {
          { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x', tooltip = function(w)
            return 'dynamic: ' .. w.id
          end } } },
        },
      })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      s:_show_tooltip()
      local tbuf = vim.api.nvim_win_get_buf(s.tooltip_win)
      assert.are.same({ 'dynamic: w1' }, vim.api.nvim_buf_get_lines(tbuf, 0, -1, false))
    end)

    it('_close_tooltip closes it', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x', tooltip = 'hi' } } } } })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      s:_show_tooltip()
      local twin = s.tooltip_win
      s:_close_tooltip()
      assert.is_nil(s.tooltip_win)
      assert.is_false(vim.api.nvim_win_is_valid(twin))
    end)

    it('does nothing for a widget with no tooltip', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = { { id = 'w1', text = 'x' } } } } })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 2, 0 })
      s:_show_tooltip()
      assert.is_nil(s.tooltip_win)
    end)

    it('does nothing on a section header line', function()
      local s = new({ sections = { { id = 'a', title = 'A', widgets = {} } } })
      s:open()
      vim.api.nvim_win_set_cursor(s.win, { 1, 0 })
      s:_show_tooltip()
      assert.is_nil(s.tooltip_win)
    end)
  end)

  describe('animation', function()
    it('animates size from small to the target over time', function()
      local s = new({ position = 'right', width = 30, animate = true, animate_ms = 5, animate_steps = 5 })
      s:open()
      -- immediately after open() the window exists but hasn't reached
      -- full size yet (it started at 1 and ramps up on timer ticks)
      assert.is_true(vim.api.nvim_win_get_width(s.win) <= 30)
      vim.wait(1000, function()
        return vim.api.nvim_win_get_width(s.win) == 30
      end, 10)
      assert.are.equal(30, vim.api.nvim_win_get_width(s.win))
    end)

    it('animates the close down before actually closing the window', function()
      local s = new({ position = 'right', width = 30, animate = true, animate_ms = 5, animate_steps = 5 })
      s:open()
      vim.wait(1000, function()
        return vim.api.nvim_win_get_width(s.win) == 30
      end, 10)
      s:close()
      vim.wait(1000, function()
        return not s:is_open()
      end, 10)
      assert.is_false(s:is_open())
    end)
  end)
end)

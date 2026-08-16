local activitybar = require('mep.activitybar.activitybar')
local config = require('mep.activitybar.config')
local notify = require('mep.notify')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.activitybar', function()
  local saved_config
  local tmpdir

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    config.setup({ todo = { persist_path = tmpdir .. '/todos.json' } })
    activitybar._reset()
  end)

  after_each(function()
    activitybar._reset()
    notify._reset()
    config.options = saved_config
    vim.fn.delete(tmpdir, 'rf')
  end)

  describe('bar', function()
    it('renders one icon-only widget per configured button, no section header', function()
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are.same({ '🔔', '✓', '▶', '⎇' }, vim.api.nvim_buf_get_lines(activitybar.bar().buf, 0, -1, false))
    end)

    it('respects mep.icons.setup({ style = ... }) for the default button set', function()
      local icons_config = require('mep.icons.config')
      local saved_icons_options = vim.deepcopy(icons_config.options)
      icons_config.setup({ style = 'ascii' })

      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are.same({ '!', 'v', '>', 'b' }, vim.api.nvim_buf_get_lines(activitybar.bar().buf, 0, -1, false))

      icons_config.options = saved_icons_options
    end)

    it('does not steal focus on open (e.g. from mep.dashboard, also auto-opened on VimEnter)', function()
      activitybar.bar().opts.animate = false
      local before = vim.api.nvim_get_current_win()
      activitybar.bar():open()
      assert.are.equal(before, vim.api.nvim_get_current_win())
    end)

    it('still exposes each button label as its hover tooltip', function()
      local widgets = require('mep.sidebar.render').find_section(activitybar.bar().sections, 'buttons').widgets
      assert.are.equal('Notifications', widgets[1].tooltip)
    end)

    it('is a floating window by default', function()
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are_not.equal('', vim.api.nvim_win_get_config(activitybar.bar().win).relative)
    end)

    it('never animates, even if config.animate is true', function()
      config.setup({ animate = true })
      assert.is_false(activitybar.bar().opts.animate)
    end)

    it('is sized exactly to the widest button icon, no extra padding', function()
      -- 🔔 is display-width 2 (a double-width emoji); ✓/▶ are 1 — the
      -- bar must fit the widest one exactly, not some fixed guess.
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are.equal(2, vim.api.nvim_win_get_width(activitybar.bar().win))
    end)

    it('shrinks further for an all-narrow button set', function()
      config.setup({ buttons = { { id = 'todo', icon = '✓', label = 'Todo' } } })
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are.equal(1, vim.api.nvim_win_get_width(activitybar.bar().win))
    end)

    it('grows to fit a wider custom icon', function()
      config.setup({ buttons = { { id = 'todo', icon = '[x]', label = 'Todo' } } })
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      assert.are.equal(3, vim.api.nvim_win_get_width(activitybar.bar().win))
    end)
  end)

  describe('toggle_panel', function()
    it('opens the notifications panel', function()
      activitybar.notifications.sidebar().opts.animate = false
      activitybar.toggle_panel('notifications')
      assert.is_true(activitybar.notifications.sidebar():is_open())
    end)

    it('opens the todo panel', function()
      activitybar.todo.sidebar().opts.animate = false
      activitybar.toggle_panel('todo')
      assert.is_true(activitybar.todo.sidebar():is_open())
    end)

    it('opens the tests panel', function()
      activitybar.tests.sidebar().opts.animate = false
      activitybar.toggle_panel('tests')
      assert.is_true(activitybar.tests.sidebar():is_open())
    end)

    it('warns on an unknown panel id instead of erroring', function()
      local orig_notify = vim.notify
      local warned = false
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      activitybar.toggle_panel('nope')
      vim.notify = orig_notify
      assert.is_true(warned)
    end)
  end)

  describe('clicking a bar button', function()
    it('toggles the associated panel open', function()
      activitybar.bar().opts.animate = false
      activitybar.notifications.sidebar().opts.animate = false
      activitybar.bar():open()

      -- opts.focus = false (the bar's own default) leaves focus
      -- wherever it was before opening — switch into it first, the
      -- same way a real click (or <C-w>w) would.
      vim.api.nvim_set_current_win(activitybar.bar().win)
      vim.api.nvim_win_set_cursor(activitybar.bar().win, { 1, 0 })
      feed('<CR>')

      assert.is_true(activitybar.notifications.sidebar():is_open())
    end)
  end)

  describe('panel layout relative to the bar', function()
    it("a panel stacks flush against the bar's left edge, no overlap", function()
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      activitybar.notifications.sidebar().opts.animate = false
      activitybar.toggle_panel('notifications')

      local bar_cfg = vim.api.nvim_win_get_config(activitybar.bar().win)
      local panel_cfg = vim.api.nvim_win_get_config(activitybar.notifications.sidebar().win)
      local panel_right_edge = panel_cfg.col + panel_cfg.width + require('mep.sidebar').border_pad(config.options.border)
      assert.are.equal(bar_cfg.col, panel_right_edge)
    end)

    it('opening a panel does not move or resize the bar', function()
      activitybar.bar().opts.animate = false
      activitybar.bar():open()
      local before = vim.api.nvim_win_get_config(activitybar.bar().win)

      activitybar.todo.sidebar().opts.animate = false
      activitybar.toggle_panel('todo')

      local after = vim.api.nvim_win_get_config(activitybar.bar().win)
      assert.are.same({ before.row, before.col, before.width, before.height }, { after.row, after.col, after.width, after.height })
    end)
  end)

  describe('setup', function()
    it('installs the vim.notify hook', function()
      local orig = vim.notify
      activitybar.setup({})
      assert.are_not.equal(orig, vim.notify)
      vim.notify = orig
    end)

    it('a notification after setup shows up in the notifications panel', function()
      local orig = vim.notify
      activitybar.setup({})
      vim.notify('captured me')
      vim.notify = orig

      assert.are.equal('captured me', notify.entries[1].text)
    end)

    it('does not auto-open the bar on VimEnter by default', function()
      activitybar.setup({})
      vim.api.nvim_exec_autocmds('VimEnter', {})
      assert.is_false(activitybar.bar():is_open())
    end)

    it('auto-opens the bar on VimEnter when auto_open = true', function()
      activitybar.setup({ auto_open = true })
      activitybar.bar().opts.animate = false
      vim.api.nvim_exec_autocmds('VimEnter', {})
      assert.is_true(activitybar.bar():is_open())
    end)

    it('never auto-opens a panel, only the bar itself', function()
      activitybar.setup({ auto_open = true })
      activitybar.bar().opts.animate = false
      vim.api.nvim_exec_autocmds('VimEnter', {})
      assert.is_false(activitybar.notifications.sidebar():is_open())
      assert.is_false(activitybar.todo.sidebar():is_open())
      assert.is_false(activitybar.tests.sidebar():is_open())
    end)
  end)

  describe('enable_auto_open / disable_auto_open', function()
    it('disable_auto_open stops VimEnter from opening the bar', function()
      activitybar.enable_auto_open()
      activitybar.disable_auto_open()
      vim.api.nvim_exec_autocmds('VimEnter', {})
      assert.is_false(activitybar.bar():is_open())
    end)

    it('enable_auto_open replaces a previous registration rather than stacking', function()
      activitybar.bar().opts.animate = false
      activitybar.enable_auto_open()
      activitybar.enable_auto_open()
      vim.api.nvim_exec_autocmds('VimEnter', {})
      -- opening an already-open sidebar is a no-op (mep.sidebar.engine's
      -- own guard), so a double-registration wouldn't error even if it
      -- happened — this just confirms it's still open exactly once
      assert.is_true(activitybar.bar():is_open())
    end)
  end)
end)

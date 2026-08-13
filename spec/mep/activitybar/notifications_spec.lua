local notifications = require('mep.activitybar.notifications')
local config = require('mep.activitybar.config')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.notifications', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    notifications._reset()
  end)

  after_each(function()
    notifications._reset()
    config.options = saved_config
  end)

  describe('add / dismiss / clear', function()
    it('adds an entry, newest first', function()
      notifications.add('first', vim.log.levels.INFO)
      notifications.add('second', vim.log.levels.WARN)
      assert.are.equal('second', notifications.entries[1].text)
      assert.are.equal('first', notifications.entries[2].text)
    end)

    it('trims to config.notifications.max_entries', function()
      config.setup({ notifications = { max_entries = 3 } })
      for i = 1, 5 do
        notifications.add('n' .. i)
      end
      assert.are.equal(3, #notifications.entries)
      assert.are.equal('n5', notifications.entries[1].text)
    end)

    it('dismiss removes just the matching entry', function()
      notifications.add('a')
      notifications.add('b')
      local id_b = notifications.entries[1].id
      notifications.dismiss(id_b)
      assert.are.equal(1, #notifications.entries)
      assert.are.equal('a', notifications.entries[1].text)
    end)

    it('clear empties everything', function()
      notifications.add('a')
      notifications.add('b')
      notifications.clear()
      assert.are.same({}, notifications.entries)
    end)
  end)

  describe('sections', function()
    it('shows a placeholder when there are no entries', function()
      local sections = notifications.sections()
      assert.are.equal('No notifications', sections[1].widgets[1].text)
    end)

    it('shows a "Clear all" widget first, then one per entry', function()
      notifications.add('a')
      notifications.add('b')
      local widgets = notifications.sections()[1].widgets
      assert.are.equal('Clear all', widgets[1].text)
      assert.are.equal('b', widgets[2].text)
      assert.are.equal('a', widgets[3].text)
    end)

    it('colors an entry by its level', function()
      notifications.add('oops', vim.log.levels.ERROR)
      local widgets = notifications.sections()[1].widgets
      assert.are.equal('DiagnosticError', widgets[2].hl)
    end)

    it("an entry's on_click dismisses it", function()
      notifications.add('a')
      local widget = notifications.sections()[1].widgets[2]
      widget.on_click(widget)
      assert.are.same({}, notifications.entries)
    end)
  end)

  describe('install / uninstall', function()
    it('captures a real vim.notify call as an entry and still calls through', function()
      local passthrough_called = false
      local orig = vim.notify
      vim.notify = function()
        passthrough_called = true
      end
      -- install() must snapshot *this* stub as "the real notify" to
      -- prove it always calls through, not just happens to work because
      -- the real vim.notify was still in place
      notifications.install()
      vim.notify('hello', vim.log.levels.WARN)
      vim.notify = orig

      assert.are.equal(1, #notifications.entries)
      assert.are.equal('hello', notifications.entries[1].text)
      assert.is_true(passthrough_called)
    end)

    it('is idempotent', function()
      local orig = vim.notify
      notifications.install()
      local wrapped = vim.notify
      notifications.install()
      assert.are.equal(wrapped, vim.notify)
      vim.notify = orig
    end)

    it('uninstall restores the original vim.notify', function()
      local orig = vim.notify
      notifications.install()
      notifications.uninstall()
      assert.are.equal(orig, vim.notify)
    end)
  end)

  describe('sidebar / toggle', function()
    after_each(function()
      pcall(function()
        notifications.sidebar():close()
      end)
    end)

    it('toggle opens the panel with current entries rendered', function()
      notifications.add('hello there')
      notifications.sidebar().opts.animate = false
      notifications.toggle()
      assert.is_true(notifications.sidebar():is_open())
      local lines = vim.api.nvim_buf_get_lines(notifications.sidebar().buf, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find('hello there', 1, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('activating a notification widget dismisses it live', function()
      notifications.add('dismiss me')
      notifications.sidebar().opts.animate = false
      notifications.toggle()
      vim.api.nvim_win_set_cursor(notifications.sidebar().win, { 2, 0 })
      feed('<CR>')
      assert.are.same({}, notifications.entries)
    end)
  end)
end)

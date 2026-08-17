local notify = require('mep.notify')
local config = require('mep.notify.config')
local popup = require('mep.notify.popup')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.notify', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    notify._reset()
  end)

  after_each(function()
    notify._reset()
    config.options = saved_options
    -- setup() binds config.options.keymaps.toggle globally with no
    -- disable() counterpart (mep.git.git's own bind_global_keymaps has
    -- the same leak risk, per its git_spec.lua teardown comment) — clean
    -- up whatever a test's own setup() may have bound, default or
    -- overridden, so it doesn't leak into later spec files.
    for _, lhs in ipairs({ '<F7>' }) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    for _, lhs in ipairs(config.defaults.keymaps.toggle) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  describe('add / dismiss / clear', function()
    it('adds an entry, newest first', function()
      notify.add('first', vim.log.levels.INFO)
      notify.add('second', vim.log.levels.WARN)
      assert.are.equal('second', notify.entries[1].text)
      assert.are.equal('first', notify.entries[2].text)
    end)

    it('defaults level to INFO', function()
      notify.add('x')
      assert.are.equal(vim.log.levels.INFO, notify.entries[1].level)
    end)

    it('records opts.title', function()
      notify.add('x', vim.log.levels.INFO, { title = 'Heads up' })
      assert.are.equal('Heads up', notify.entries[1].title)
    end)

    it('trims to config.options.max_entries', function()
      config.setup({ max_entries = 3 })
      for i = 1, 5 do
        notify.add('n' .. i)
      end
      assert.are.equal(3, #notify.entries)
      assert.are.equal('n5', notify.entries[1].text)
    end)

    it('dismiss removes just the matching entry', function()
      notify.add('a')
      notify.add('b')
      local id_b = notify.entries[1].id
      notify.dismiss(id_b)
      assert.are.equal(1, #notify.entries)
      assert.are.equal('a', notify.entries[1].text)
    end)

    it('clear empties everything', function()
      notify.add('a')
      notify.add('b')
      notify.clear()
      assert.are.same({}, notify.entries)
    end)

    it('returns the created entry', function()
      local entry = notify.add('x', vim.log.levels.WARN)
      assert.are.equal('x', entry.text)
      assert.are.equal(vim.log.levels.WARN, entry.level)
    end)
  end)

  describe('sections', function()
    it('shows a placeholder when there are no entries', function()
      local sections = notify.sections()
      assert.are.equal('No notifications', sections[1].widgets[1].text)
    end)

    it('shows a "Clear all" widget first, then one per entry', function()
      notify.add('a')
      notify.add('b')
      local widgets = notify.sections()[1].widgets
      assert.are.equal('Clear all', widgets[1].text)
      assert.are.equal('b', widgets[2].text)
      assert.are.equal('a', widgets[3].text)
    end)

    it('colors and icons an entry by its level, via MepNotify* groups', function()
      notify.add('oops', vim.log.levels.ERROR)
      local widgets = notify.sections()[1].widgets
      assert.are.equal('MepNotifyError', widgets[2].hl)
      assert.are.equal(config.options.icons[vim.log.levels.ERROR], widgets[2].icon)
    end)

    it('prefixes the title onto the widget text when present', function()
      notify.add('body', vim.log.levels.INFO, { title = 'Heads up' })
      local widgets = notify.sections()[1].widgets
      assert.are.equal('Heads up: body', widgets[2].text)
    end)

    it("an entry's on_click dismisses it", function()
      notify.add('a')
      local widget = notify.sections()[1].widgets[2]
      widget.on_click(widget)
      assert.are.same({}, notify.entries)
    end)
  end)

  describe('install / uninstall / notify', function()
    it('captures a real vim.notify call as a history entry', function()
      local orig = vim.notify
      notify.install()
      vim.notify('hello', vim.log.levels.WARN)
      vim.notify = orig

      assert.are.equal(1, #notify.entries)
      assert.are.equal('hello', notify.entries[1].text)
    end)

    it('does NOT forward to the previous vim.notify (unlike the old activitybar hook)', function()
      local passthrough_called = false
      local orig = vim.notify
      vim.notify = function()
        passthrough_called = true
      end
      notify.install()
      vim.notify('hello')
      vim.notify = orig

      assert.is_false(passthrough_called)
    end)

    it('shows a real popup toast alongside the history entry', function()
      notify.install()
      vim.notify('hello', vim.log.levels.INFO)
      assert.are.equal(1, popup.count())
    end)

    it('is idempotent', function()
      local orig = vim.notify
      notify.install()
      local wrapped = vim.notify
      notify.install()
      assert.are.equal(wrapped, vim.notify)
      vim.notify = orig
    end)

    it('uninstall restores the original vim.notify', function()
      local orig = vim.notify
      notify.install()
      notify.uninstall()
      assert.are.equal(orig, vim.notify)
    end)
  end)

  describe('attach / multiple sidebars stay in sync', function()
    it('redraws every attached sidebar when an entry is added', function()
      local sidebar_mod = require('mep.sidebar')
      local sb1 = notify.attach(sidebar_mod.new({ sections = notify.sections(), animate = false }))
      local sb2 = notify.attach(sidebar_mod.new({ sections = notify.sections(), animate = false }))
      sb1:open()
      sb2:open()

      notify.add('shared entry')

      local function has_entry(sb)
        for _, line in ipairs(vim.api.nvim_buf_get_lines(sb.buf, 0, -1, false)) do
          if line:find('shared entry', 1, true) then
            return true
          end
        end
        return false
      end

      assert.is_true(has_entry(sb1))
      assert.is_true(has_entry(sb2))

      pcall(function()
        sb1:close()
      end)
      pcall(function()
        sb2:close()
      end)
    end)
  end)

  describe('bind_dismiss_keymaps', function()
    it('d dismisses the notification under the cursor', function()
      notify.add('dismiss me')
      notify.sidebar().opts.animate = false
      notify.toggle()
      -- row 1 = the section header ("▾ Notifications"), row 2 = the
      -- "Clear all" widget, row 3 = this single entry.
      vim.api.nvim_win_set_cursor(notify.sidebar().win, { 3, 0 })
      feed('d')
      assert.are.same({}, notify.entries)
    end)

    it('d on the "Clear all" row does nothing (only a real entry is dismissible by id)', function()
      notify.add('keep me')
      notify.sidebar().opts.animate = false
      notify.toggle()
      vim.api.nvim_win_set_cursor(notify.sidebar().win, { 2, 0 })
      feed('d')
      assert.are.equal(1, #notify.entries)
    end)

    it('C clears every notification', function()
      notify.add('a')
      notify.add('b')
      notify.sidebar().opts.animate = false
      notify.toggle()
      feed('C')
      assert.are.same({}, notify.entries)
    end)
  end)

  describe('sidebar / toggle', function()
    it('toggle opens the standalone panel with current entries rendered', function()
      notify.add('hello there')
      notify.sidebar().opts.animate = false
      notify.toggle()
      assert.is_true(notify.sidebar():is_open())
      local lines = vim.api.nvim_buf_get_lines(notify.sidebar().buf, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find('hello there', 1, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('activating a notification widget dismisses it live', function()
      notify.add('dismiss me')
      notify.sidebar().opts.animate = false
      notify.toggle()
      vim.api.nvim_win_set_cursor(notify.sidebar().win, { 3, 0 })
      feed('<CR>')
      assert.are.same({}, notify.entries)
    end)

    it("the standalone panel is sized from mep.notify's own panel config, not mep.activitybar's", function()
      config.setup({ panel = { position = 'left', width = 77, float = false, border = 'none', animate = false } })
      local sb = notify.sidebar()
      assert.are.equal('left', sb.opts.position)
      assert.are.equal(77, sb.opts.width)
      assert.is_false(sb.opts.float)
    end)
  end)

  describe('setup', function()
    it('installs the hook', function()
      local orig = vim.notify
      notify.setup({})
      assert.are_not.equal(orig, vim.notify)
      vim.notify = orig
    end)

    it('applies config', function()
      notify.setup({ max_entries = 5 })
      assert.are.equal(5, config.options.max_entries)
    end)

    it('binds keymaps.toggle to open/close the standalone panel', function()
      notify.setup({ keymaps = { toggle = { '<F7>' } } })
      notify.sidebar().opts.animate = false
      feed('<F7>')
      assert.is_true(notify.sidebar():is_open())
      feed('<F7>')
      assert.is_false(notify.sidebar():is_open())
    end)
  end)
end)

-- mep.activitybar.notifications is a thin mep.sidebar view attached to
-- mep.notify (the same "same content, differently-sized host sidebar"
-- pattern spec/mep/activitybar/git_spec.lua exercises for mep.git.
-- sidebar) — this file only tests the delegation/sizing/wiring, not the
-- underlying entry-list/hook logic, which spec/mep/notify/notify_spec.lua
-- already covers directly.
local notifications = require('mep.activitybar.notifications')
local config = require('mep.activitybar.config')
local notify = require('mep.notify')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.notifications', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    notifications._reset()
    notify._reset()
  end)

  after_each(function()
    notifications._reset()
    notify._reset()
    config.options = saved_config
  end)

  describe('sidebar', function()
    it("sizes/positions the panel from mep.activitybar's own config", function()
      config.setup({ position = 'left', panel_width = 55, float = false, border = 'none' })
      local sb = notifications.sidebar()
      assert.are.equal('left', sb.opts.position)
      assert.are.equal(55, sb.opts.width)
      assert.is_false(sb.opts.float)
    end)

    it('attaches to mep.notify, so an entry added elsewhere shows up here too', function()
      notifications.sidebar().opts.animate = false
      notifications.sidebar():open()
      notify.add('from elsewhere')
      local lines = vim.api.nvim_buf_get_lines(notifications.sidebar().buf, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find('from elsewhere', 1, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('a dismiss here removes it from mep.notify itself, not a separate copy', function()
      notify.add('dismiss me')
      notifications.sidebar().opts.animate = false
      notifications.toggle()
      -- row 1 = section header, row 2 = "Clear all", row 3 = this entry
      vim.api.nvim_win_set_cursor(notifications.sidebar().win, { 3, 0 })
      feed('<CR>')
      assert.are.same({}, notify.entries)
    end)
  end)

  describe('toggle', function()
    it('opens the panel with current mep.notify entries rendered', function()
      notify.add('hello there')
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
  end)

  describe('_reset', function()
    it('closes its own sidebar but leaves mep.notify entries untouched', function()
      notify.add('survives')
      notifications.sidebar().opts.animate = false
      notifications.sidebar():open()
      notifications._reset()
      assert.are.equal(1, #notify.entries)
    end)
  end)
end)

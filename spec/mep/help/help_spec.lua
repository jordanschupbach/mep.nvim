local help = require('mep.help')
local commands_mod = require('mep.picker.sources.commands')
local whichkey_mod = require('mep.whichkey')

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.help', function()
  describe('run', function()
    it('opens a real :help tag for a doc item', function()
      -- Whether or not doc/tags has been generated for this checkout,
      -- run() must not error either way — just pcalls vim.cmd('help
      -- ...') and notifies on failure.
      assert.has_no.errors(function()
        help.run({ kind = 'doc', tag = 'mep-hints' })
      end)
      pcall(vim.cmd, 'helpclose')
    end)

    it('notifies instead of erroring for an unresolvable tag', function()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      help.run({ kind = 'doc', tag = 'mep-definitely-not-a-real-tag' })
      vim.notify = orig_notify
      assert.matches('no :help tag', notified)
    end)

    it('runs a command item via mep.picker.sources.commands.run', function()
      local ran = false
      vim.api.nvim_create_user_command('MepHelpSpecRun', function()
        ran = true
      end, {})
      help.run({ kind = 'command', cmd = { name = 'MepHelpSpecRun', nargs = '0' } })
      assert.is_true(ran)
      vim.api.nvim_del_user_command('MepHelpSpecRun')
    end)

    it('executes a keymap item via mep.whichkey.execute', function()
      local orig_execute = whichkey_mod.execute
      local seen
      whichkey_mod.execute = function(m)
        seen = m
      end
      local dummy_map = { lhs = 'x' }
      help.run({ kind = 'keymap', m = dummy_map })
      whichkey_mod.execute = orig_execute
      assert.are.equal(dummy_map, seen)
    end)
  end)

  describe('picker', function()
    it('opens a mep.picker instance', function()
      help.picker()
      -- The picker floats as the current window; close it so the spec
      -- suite doesn't leak a stray floating window into later specs.
      local win = vim.api.nvim_get_current_win()
      assert.are.equal('editor', vim.api.nvim_win_get_config(win).relative)
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('setup', function()
    it('binds the configured picker keymap', function()
      local keymaps = { picker = { '<localleader>hp1' } }
      help.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>hp1', 'n', false, true)))
      del_all(keymaps.picker)
    end)

    it('returns the resolved options', function()
      local options = help.setup({ keymaps = { picker = {} } })
      assert.are.same({}, options.keymaps.picker)
    end)
  end)
end)

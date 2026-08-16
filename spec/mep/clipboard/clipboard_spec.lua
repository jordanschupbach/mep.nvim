local clipboard = require('mep.clipboard')
local config = require('mep.clipboard.config')
local platform = require('mep.clipboard.platform')

describe('mep.clipboard', function()
  local saved_options, saved_clipboard, saved_g_clipboard
  local orig_is_ssh, orig_has_local_tool

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    saved_clipboard = vim.o.clipboard
    saved_g_clipboard = vim.g.clipboard
    orig_is_ssh = platform.is_ssh
    orig_has_local_tool = platform.has_local_tool
  end)

  after_each(function()
    config.options = saved_options
    vim.o.clipboard = saved_clipboard
    vim.g.clipboard = saved_g_clipboard
    platform.is_ssh = orig_is_ssh
    platform.has_local_tool = orig_has_local_tool
  end)

  describe('setup', function()
    it('sets clipboard=unnamedplus by default', function()
      vim.o.clipboard = ''
      clipboard.setup({})
      assert.matches('unnamedplus', vim.o.clipboard)
    end)

    it('leaves clipboard untouched when unnamedplus = false', function()
      vim.o.clipboard = ''
      clipboard.setup({ unnamedplus = false })
      assert.are.equal('', vim.o.clipboard)
    end)

    it('is a full no-op when enable = false', function()
      vim.o.clipboard = ''
      vim.g.clipboard = nil
      platform.is_ssh = function()
        return true
      end
      platform.has_local_tool = function()
        return false
      end
      clipboard.setup({ enable = false })
      assert.are.equal('', vim.o.clipboard)
      assert.is_nil(vim.g.clipboard)
    end)

    it('wires OSC52 when SSH and no local tool are both true', function()
      vim.g.clipboard = nil
      platform.is_ssh = function()
        return true
      end
      platform.has_local_tool = function()
        return false
      end
      clipboard.setup({})
      assert.is_not_nil(vim.g.clipboard)
      assert.are.equal('OSC 52', vim.g.clipboard.name)
      assert.is_function(vim.g.clipboard.copy['+'])
      assert.is_function(vim.g.clipboard.paste['+'])
      assert.is_function(vim.g.clipboard.copy['*'])
      assert.is_function(vim.g.clipboard.paste['*'])
    end)

    it('does not wire OSC52 when SSH but a local tool is available', function()
      vim.g.clipboard = nil
      platform.is_ssh = function()
        return true
      end
      platform.has_local_tool = function()
        return true
      end
      clipboard.setup({})
      assert.is_nil(vim.g.clipboard)
    end)

    it('does not wire OSC52 when not over SSH, even with no local tool', function()
      vim.g.clipboard = nil
      platform.is_ssh = function()
        return false
      end
      platform.has_local_tool = function()
        return false
      end
      clipboard.setup({})
      assert.is_nil(vim.g.clipboard)
    end)

    it('does not wire OSC52 when osc52.enable = false, even if otherwise applicable', function()
      vim.g.clipboard = nil
      platform.is_ssh = function()
        return true
      end
      platform.has_local_tool = function()
        return false
      end
      clipboard.setup({ osc52 = { enable = false } })
      assert.is_nil(vim.g.clipboard)
    end)

    it('returns the resolved options', function()
      local options = clipboard.setup({ unnamedplus = false })
      assert.is_false(options.unnamedplus)
    end)
  end)
end)

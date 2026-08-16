local index = require('mep.help.index')
local config = require('mep.help.config')

local function find(items, kind, predicate)
  for _, item in ipairs(items) do
    if item.kind == kind and predicate(item) then
      return item
    end
  end
  return nil
end

describe('mep.help.index', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  describe('build', function()
    it('includes a curated library description', function()
      local items = index.build(vim.api.nvim_get_current_buf())
      local item = find(items, 'doc', function(i)
        return i.tag == 'mep-hints'
      end)
      assert.is_not_nil(item)
      assert.matches(':help mep%-hints', item.text)
    end)

    it('includes a config.options.descriptions override', function()
      config.setup({ descriptions = { my_lib = { desc = 'a test library', tag = 'my-lib' } } })
      local items = index.build(vim.api.nvim_get_current_buf())
      local item = find(items, 'doc', function(i)
        return i.tag == 'my-lib'
      end)
      assert.is_not_nil(item)
      assert.matches('a test library', item.text)
    end)

    it('includes a real Ex command', function()
      vim.api.nvim_create_user_command('MepHelpSpecFoo', function() end, { desc = 'a test command' })
      local items = index.build(vim.api.nvim_get_current_buf())
      local item = find(items, 'command', function(i)
        return i.cmd.name == 'MepHelpSpecFoo'
      end)
      assert.is_not_nil(item)
      assert.matches('a test command', item.text)
      vim.api.nvim_del_user_command('MepHelpSpecFoo')
    end)

    it('includes a real normal-mode keymap with its desc', function()
      vim.keymap.set('n', '<localleader>hspecx', function() end, { desc = 'a test keymap' })
      local items = index.build(vim.api.nvim_get_current_buf())
      local item = find(items, 'keymap', function(i)
        return i.text:match('a test keymap')
      end)
      assert.is_not_nil(item)
      pcall(vim.keymap.del, 'n', '<localleader>hspecx')
    end)

    it('includes a buffer-local keymap for the given buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.keymap.set('n', '<localleader>hspecy', function() end, { buffer = buf, desc = 'buffer-local test keymap' })
      local items = index.build(buf)
      local item = find(items, 'keymap', function(i)
        return i.text:match('buffer%-local test keymap')
      end)
      assert.is_not_nil(item)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

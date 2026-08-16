local completion = require('mep.completion.completion')
local config = require('mep.completion.config')
local engine = require('mep.completion.engine')

describe('mep.completion.completion', function()
  local saved_config
  local orig_enable

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    orig_enable = engine.enable
  end)

  after_each(function()
    config.options = saved_config
    engine.enable = orig_enable
    engine.disable()
  end)

  describe('sources', function()
    it('registers the four built-in sources', function()
      assert.is_not_nil(completion.sources.lsp)
      assert.is_not_nil(completion.sources.buffer)
      assert.is_not_nil(completion.sources.path)
      assert.is_not_nil(completion.sources.snippet)
    end)

    it('each has a complete function', function()
      for name, source in pairs(completion.sources) do
        assert.are.equal('function', type(source.complete), name .. ' has no complete()')
      end
    end)
  end)

  describe('setup', function()
    it('returns the resolved config', function()
      engine.enable = function() end
      local opts = completion.setup({ min_chars = 3 })
      assert.are.equal(3, opts.min_chars)
    end)

    it('enables the engine', function()
      local called = false
      engine.enable = function()
        called = true
      end
      completion.setup({})
      assert.is_true(called)
    end)

    it('warns about an unrecognized source name but does not error', function()
      engine.enable = function() end
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      assert.has_no.errors(function()
        completion.setup({ sources = { 'nope' } })
      end)
      vim.notify = orig_notify
      assert.is_true(warned)
    end)

    it('does not warn for known source names', function()
      engine.enable = function() end
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      completion.setup({ sources = { 'lsp', 'buffer' } })
      vim.notify = orig_notify
      assert.is_false(warned)
    end)
  end)
end)

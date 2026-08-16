local languages = require('mep.run.languages')
local config = require('mep.run.config')

describe('mep.run.languages', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  describe('resolve', function()
    it('passes through a filetype that already matches a babel key', function()
      assert.are.equal('python', languages.resolve('python'))
      assert.are.equal('lua', languages.resolve('lua'))
    end)

    it('maps a curated filetype to its own babel key', function()
      assert.are.equal('csharp', languages.resolve('cs'))
      assert.are.equal('sh', languages.resolve('bash'))
      assert.are.equal('javascript', languages.resolve('javascriptreact'))
    end)

    it('prefers a config override over the curated mapping', function()
      config.setup({ filetype_to_babel = { cs = 'not-csharp' } })
      assert.are.equal('not-csharp', languages.resolve('cs'))
    end)

    it('prefers a config override even for a filetype with no curated entry', function()
      config.setup({ filetype_to_babel = { zig_variant = 'zig' } })
      assert.are.equal('zig', languages.resolve('zig_variant'))
    end)
  end)
end)

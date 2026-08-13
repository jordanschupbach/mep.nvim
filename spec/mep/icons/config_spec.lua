local config = require('mep.icons.config')

describe('mep.icons.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('defaults to the nerd_font style with no overrides', function()
    assert.are.equal('nerd_font', config.defaults.style)
    assert.are.same({}, config.defaults.overrides)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('setup(opts) overrides the style', function()
    local opts = config.setup({ style = 'ascii' })
    assert.are.equal('ascii', opts.style)
  end)

  it('deep-merges overrides, preserving the style default', function()
    local opts = config.setup({ overrides = { emoji = { by_extension = { lua = '🌛' } } } })
    assert.are.equal('nerd_font', opts.style)
    assert.are.equal('🌛', opts.overrides.emoji.by_extension.lua)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ style = 'ascii' })
    assert.are.equal('nerd_font', config.defaults.style)
  end)
end)

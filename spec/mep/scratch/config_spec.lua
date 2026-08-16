local config = require('mep.scratch.config')

describe('mep.scratch.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('scratch', config.defaults.name)
    assert.are.equal('', config.defaults.filetype)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides filetype independently of name', function()
    local opts = config.setup({ filetype = 'markdown' })
    assert.are.equal('markdown', opts.filetype)
    assert.are.equal('scratch', opts.name)
  end)

  it('overrides name independently of filetype', function()
    local opts = config.setup({ name = 'notes' })
    assert.are.equal('notes', opts.name)
    assert.are.equal('', opts.filetype)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ name = 'notes' })
    assert.are.equal('scratch', config.defaults.name)
  end)
end)

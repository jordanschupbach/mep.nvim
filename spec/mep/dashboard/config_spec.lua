local config = require('mep.dashboard.config')

describe('mep.dashboard.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.auto_open)
    assert.are.equal('intro', config.defaults.content)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides auto_open independently of content', function()
    local opts = config.setup({ auto_open = false })
    assert.is_false(opts.auto_open)
    assert.are.equal('intro', opts.content)
  end)

  it('accepts a function as content without erroring', function()
    local fn = function()
      return { 'custom' }
    end
    local opts = config.setup({ content = fn })
    assert.are.equal(fn, opts.content)
  end)

  it('accepts a plain list as content without erroring', function()
    local opts = config.setup({ content = { 'a', 'b' } })
    assert.are.same({ 'a', 'b' }, opts.content)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ auto_open = false })
    assert.is_true(config.defaults.auto_open)
  end)
end)

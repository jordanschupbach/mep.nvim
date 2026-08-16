local config = require('mep.hints.config')

describe('mep.hints.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('asdfghjklqwertyuiopzxcvbnm', config.defaults.labels)
    assert.are.same({}, config.defaults.triggers.char)
    assert.are.same({}, config.defaults.triggers.word)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('deep-merges a partial override, preserving sibling trigger defaults', function()
    local opts = config.setup({ triggers = { char = { 's' } } })
    assert.are.same({ 's' }, opts.triggers.char)
    assert.are.same({}, opts.triggers.word)
    assert.are.equal(config.defaults.labels, opts.labels)
  end)

  it('overrides the label charset', function()
    local opts = config.setup({ labels = 'abc' })
    assert.are.equal('abc', opts.labels)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ labels = 'xyz', triggers = { word = { 'w' } } })
    assert.are.equal('asdfghjklqwertyuiopzxcvbnm', config.defaults.labels)
    assert.are.same({}, config.defaults.triggers.word)
  end)
end)

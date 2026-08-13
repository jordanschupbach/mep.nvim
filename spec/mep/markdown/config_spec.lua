local config = require('mep.markdown.config')

describe('mep.markdown.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has all features on by default', function()
    local defaults = config.defaults
    assert.is_true(defaults.highlight)
    assert.is_true(defaults.headers)
    assert.is_true(defaults.emphasis)
    assert.is_true(defaults.gutter)
    assert.is_true(defaults.tables)
    assert.is_true(defaults.code_blocks)
    assert.are.same({ '①', '②', '③', '④', '⑤', '⑥' }, defaults.gutter_symbols)
  end)

  it('setup({}) applies the defaults', function()
    local options = config.setup({})
    assert.are.same(config.defaults, options)
  end)

  it('setup(opts) deep-merges onto a fresh copy of the defaults', function()
    local options = config.setup({ headers = false })
    assert.is_false(options.headers)
    assert.is_true(options.emphasis)
    assert.are.equal(config.defaults, config.defaults) -- setup() must not mutate defaults
    assert.is_true(config.defaults.headers)
  end)

  it('setup(opts) can override gutter_symbols', function()
    local options = config.setup({ gutter_symbols = { 'a', 'b', 'c', 'd', 'e', 'f' } })
    assert.are.same({ 'a', 'b', 'c', 'd', 'e', 'f' }, options.gutter_symbols)
  end)
end)

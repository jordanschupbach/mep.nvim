local config = require('mep.todoscan.config')

describe('mep.todoscan.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ 'TODO', 'FIXME', 'HACK', 'NOTE' }, config.defaults.keywords)
    assert.are.equal(300, config.defaults.debounce_ms)
    assert.is_true(config.defaults.highlight)
    assert.are.same({}, config.defaults.signs)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides keywords independently of debounce_ms', function()
    local opts = config.setup({ keywords = { 'XXX' } })
    assert.are.same({ 'XXX' }, opts.keywords)
    assert.are.equal(config.defaults.debounce_ms, opts.debounce_ms)
  end)

  it('overrides signs', function()
    local opts = config.setup({ signs = { TODO = '!!' } })
    assert.are.same({ TODO = '!!' }, opts.signs)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ highlight = false })
    assert.is_true(config.defaults.highlight)
  end)
end)

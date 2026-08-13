local config = require('mep.completion.config')

describe('mep.completion.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ 'lsp', 'buffer', 'path' }, config.defaults.sources)
    assert.are.equal(80, config.defaults.debounce_ms)
    assert.are.equal(1, config.defaults.min_chars)
    assert.are.equal(50, config.defaults.max_items)
    assert.is_true(config.defaults.auto_trigger)
    assert.are.same({ 'menu', 'menuone', 'noinsert' }, config.defaults.completeopt)
    assert.are.same({ '<C-Space>' }, config.defaults.keymaps.trigger)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides sources independently of debounce_ms', function()
    local opts = config.setup({ sources = { 'buffer' } })
    assert.are.same({ 'buffer' }, opts.sources)
    assert.are.equal(config.defaults.debounce_ms, opts.debounce_ms)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ min_chars = 3 })
    assert.are.equal(1, config.defaults.min_chars)
  end)
end)

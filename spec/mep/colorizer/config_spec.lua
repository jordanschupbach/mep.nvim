local config = require('mep.colorizer.config')

describe('mep.colorizer.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('background', config.defaults.mode)
    assert.is_string(config.defaults.swatch_char)
    assert.is_false(config.defaults.filetypes)
    assert.are.equal(150, config.defaults.debounce_ms)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides mode/filetypes/debounce_ms independently', function()
    local opts = config.setup({ mode = 'swatch', filetypes = { 'css' }, debounce_ms = 50 })
    assert.are.equal('swatch', opts.mode)
    assert.are.same({ 'css' }, opts.filetypes)
    assert.are.equal(50, opts.debounce_ms)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ mode = 'swatch' })
    assert.are.equal('background', config.defaults.mode)
  end)
end)

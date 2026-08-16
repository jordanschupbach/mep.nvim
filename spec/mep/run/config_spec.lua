local config = require('mep.run.config')

describe('mep.run.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.filetype_to_babel)
    assert.are.equal(0.3, config.defaults.terminal_height_ratio)
    assert.are.same({ '<leader>xr' }, config.defaults.keymaps.run)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides terminal_height_ratio/filetype_to_babel independently', function()
    local opts = config.setup({ terminal_height_ratio = 0.5, filetype_to_babel = { foo = 'bar' } })
    assert.are.equal(0.5, opts.terminal_height_ratio)
    assert.are.same({ foo = 'bar' }, opts.filetype_to_babel)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ terminal_height_ratio = 0.9 })
    assert.are.equal(0.3, config.defaults.terminal_height_ratio)
  end)
end)

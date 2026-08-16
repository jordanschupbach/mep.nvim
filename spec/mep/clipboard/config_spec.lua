local config = require('mep.clipboard.config')

describe('mep.clipboard.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.enable)
    assert.is_true(config.defaults.unnamedplus)
    assert.is_true(config.defaults.osc52.enable)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a partial osc52 override, preserving sibling defaults', function()
    local opts = config.setup({ osc52 = { enable = false } })
    assert.is_false(opts.osc52.enable)
    assert.is_true(opts.unnamedplus)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ enable = false })
    assert.is_true(config.defaults.enable)
  end)
end)

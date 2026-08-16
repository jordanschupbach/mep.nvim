local config = require('mep.zen.config')

describe('mep.zen.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal(90, config.defaults.width)
    assert.are.same({
      activitybar = true,
      filetree = true,
      symbols = true,
      gutter = true,
      chrome = true,
    }, config.defaults.hide)
    assert.are.same({ '<leader>zz' }, config.defaults.keymaps.toggle)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides width independently of hide', function()
    local opts = config.setup({ width = 120 })
    assert.are.equal(120, opts.width)
    assert.is_true(opts.hide.chrome)
  end)

  it('deep-merges a partial hide override, preserving sibling defaults', function()
    local opts = config.setup({ hide = { chrome = false } })
    assert.is_false(opts.hide.chrome)
    assert.is_true(opts.hide.activitybar)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ width = 120 })
    assert.are.equal(90, config.defaults.width)
  end)
end)

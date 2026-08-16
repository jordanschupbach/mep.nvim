local config = require('mep.symbols.config')

describe('mep.symbols.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal(0.25, config.defaults.width_ratio)
    assert.are.equal(20, config.defaults.min_width)
    assert.are.equal('right', config.defaults.position)
    assert.are.same({ '<CR>' }, config.defaults.keymaps.jump)
    assert.are.same({ 'q', '<Esc>' }, config.defaults.keymaps.close)
    assert.are.same({ 'R' }, config.defaults.keymaps.refresh)
    assert.are.same({ '<leader>ll' }, config.defaults.triggers.toggle)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('deep-merges a partial override, preserving sibling keymap defaults', function()
    local opts = config.setup({ keymaps = { close = { '<C-q>' } } })
    assert.are.same({ '<C-q>' }, opts.keymaps.close)
    assert.are.same(config.defaults.keymaps.jump, opts.keymaps.jump)
  end)

  it('overrides width_ratio/min_width/position independently', function()
    local opts = config.setup({ width_ratio = 0.3, position = 'left' })
    assert.are.equal(0.3, opts.width_ratio)
    assert.are.equal('left', opts.position)
    assert.are.equal(20, opts.min_width)
  end)

  it('overrides the trigger keymap', function()
    local opts = config.setup({ triggers = { toggle = { '<leader>o' } } })
    assert.are.same({ '<leader>o' }, opts.triggers.toggle)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ width_ratio = 0.9 })
    assert.are.equal(0.25, config.defaults.width_ratio)
  end)
end)

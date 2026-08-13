local config = require('mep.sidebar.config')

describe('mep.sidebar.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('right', config.defaults.position)
    assert.are.equal(30, config.defaults.width)
    assert.are.equal(15, config.defaults.height)
    assert.is_true(config.defaults.animate)
    assert.is_false(config.defaults.float)
    assert.are.equal('rounded', config.defaults.border)
    assert.are.equal(0, config.defaults.edge_offset)
    assert.are.equal(5, config.defaults.resize_step)
    assert.is_true(config.defaults.focus)
    assert.are.same({ '<CR>' }, config.defaults.keymaps.activate)
    assert.are.same({ 'q' }, config.defaults.keymaps.close)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides position independently of width', function()
    local opts = config.setup({ position = 'left' })
    assert.are.equal('left', opts.position)
    assert.are.equal(config.defaults.width, opts.width)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ animate = false })
    assert.is_true(config.defaults.animate)
  end)
end)

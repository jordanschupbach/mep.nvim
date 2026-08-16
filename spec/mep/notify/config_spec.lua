local config = require('mep.notify.config')

describe('mep.notify.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible popup defaults', function()
    config.setup({})
    assert.are.equal('top-right', config.defaults.position)
    assert.are.equal(30, config.defaults.min_width)
    assert.are.equal(60, config.defaults.max_width)
    assert.are.equal('rounded', config.defaults.border)
    assert.are.equal(5, config.defaults.max_visible)
  end)

  it('has an icon and a timeout for every real notification level (not the OFF sentinel)', function()
    for _, level in ipairs({
      vim.log.levels.ERROR,
      vim.log.levels.WARN,
      vim.log.levels.INFO,
      vim.log.levels.DEBUG,
      vim.log.levels.TRACE,
    }) do
      assert.is_not_nil(config.defaults.icons[level])
      assert.is_not_nil(config.defaults.timeout[level])
    end
  end)

  it('gives errors/warnings a longer timeout than info/debug', function()
    assert.is_true(config.defaults.timeout[vim.log.levels.ERROR] > config.defaults.timeout[vim.log.levels.INFO])
    assert.is_true(config.defaults.timeout[vim.log.levels.WARN] > config.defaults.timeout[vim.log.levels.INFO])
  end)

  it('has a max_entries default for history', function()
    assert.are.equal(200, config.defaults.max_entries)
  end)

  it('has default dismiss/clear keymaps for the history panel', function()
    assert.are.same({ 'd', 'x' }, config.defaults.keymaps.dismiss)
    assert.are.same({ 'C' }, config.defaults.keymaps.clear)
  end)

  it('has its own independent panel sizing, distinct from mep.activitybar', function()
    assert.are.equal('right', config.defaults.panel.position)
    assert.are.equal(50, config.defaults.panel.width)
  end)

  it('deep-merges a partial override, preserving sibling defaults', function()
    local opts = config.setup({ position = 'bottom-left' })
    assert.are.equal('bottom-left', opts.position)
    assert.are.equal(60, opts.max_width)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ max_entries = 10 })
    assert.are.equal(200, config.defaults.max_entries)
  end)
end)

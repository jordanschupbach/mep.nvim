local config = require('mep.activitybar.config')

describe('mep.activitybar.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('right', config.defaults.position)
    assert.is_nil(config.defaults.bar_width) -- computed from buttons' icons, not configured
    assert.are.equal(42, config.defaults.panel_width)
    assert.is_true(config.defaults.float)
    assert.are.equal('rounded', config.defaults.border)
    assert.is_false(config.defaults.auto_open)
    assert.are.equal(4, #config.defaults.buttons)
    assert.are.equal('notifications', config.defaults.buttons[1].id)
    assert.are.equal('git', config.defaults.buttons[4].id)
    assert.is_nil(config.defaults.todo.persist_path)
    assert.are.same({ 'busted' }, config.defaults.tests.cmd)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a nested override, preserving sibling defaults', function()
    local opts = config.setup({ tests = { cmd = { 'npm', 'test' } } })
    assert.are.same({ 'npm', 'test' }, opts.tests.cmd)
    assert.are.equal(42, opts.panel_width)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ panel_width = 60 })
    assert.are.equal(42, config.defaults.panel_width)
  end)
end)

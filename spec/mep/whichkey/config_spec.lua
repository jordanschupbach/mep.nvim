local config = require('mep.whichkey.config')

describe('mep.whichkey.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ '<leader>' }, config.defaults.triggers)
    assert.are.same({ 'n' }, config.defaults.modes)
    assert.are.equal('bottom', config.defaults.position)
    assert.are.equal('rounded', config.defaults.border)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides triggers independently of modes', function()
    local opts = config.setup({ triggers = { '<leader>', ',' } })
    assert.are.same({ '<leader>', ',' }, opts.triggers)
    assert.are.same(config.defaults.modes, opts.modes)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ border = 'single' })
    assert.are.equal('rounded', config.defaults.border)
  end)
end)

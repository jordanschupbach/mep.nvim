local config = require('mep.help.config')

describe('mep.help.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.descriptions)
    assert.are.same({ '<leader>?' }, config.defaults.keymaps.picker)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('merges a descriptions override on top of the (empty) default table', function()
    local opts = config.setup({ descriptions = { foo = { desc = 'a thing', tag = 'foo' } } })
    assert.are.same({ foo = { desc = 'a thing', tag = 'foo' } }, opts.descriptions)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ descriptions = { x = { desc = 'y', tag = 'z' } } })
    assert.are.same({}, config.defaults.descriptions)
  end)
end)

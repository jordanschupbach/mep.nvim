local config = require('mep.url.config')

describe('mep.url.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ 'gx' }, config.defaults.keymaps.open)
    assert.are.same({ 'gX' }, config.defaults.keymaps.pick)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a nested keymaps override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { open = { '<leader>gx' } } })
    assert.are.same({ '<leader>gx' }, opts.keymaps.open)
    assert.are.same({ 'gX' }, opts.keymaps.pick)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ keymaps = { pick = { 'gY' } } })
    assert.are.same({ 'gX' }, config.defaults.keymaps.pick)
  end)
end)

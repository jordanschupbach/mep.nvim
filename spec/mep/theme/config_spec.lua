local config = require('mep.theme.config')

describe('mep.theme.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('gruvbox-dark', config.defaults.default)
    assert.is_true(config.defaults.apply_on_setup)
    assert.are.same({ '<leader>ut' }, config.defaults.keymaps.picker)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides default independently of keymaps', function()
    local opts = config.setup({ default = 'nord' })
    assert.are.equal('nord', opts.default)
    assert.are.same(config.defaults.keymaps, opts.keymaps)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ apply_on_setup = false })
    assert.is_true(config.defaults.apply_on_setup)
  end)
end)

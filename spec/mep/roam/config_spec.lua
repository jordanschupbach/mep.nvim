local config = require('mep.roam.config')

describe('mep.roam.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.roam_dirs)
    assert.matches('^#%+TITLE:', config.defaults.daily_template)
    assert.are.same({ '<leader>rf' }, config.defaults.keymaps.insert)
    assert.are.same({ '<leader>rb' }, config.defaults.keymaps.backlinks)
    assert.are.same({ '<leader>rt' }, config.defaults.keymaps.today)
    assert.are.same({ '<leader>rc' }, config.defaults.keymaps.new_note)
    assert.are.equal('right', config.defaults.sidebar.position)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides roam_dirs/daily_template independently', function()
    local opts = config.setup({ roam_dirs = { '~/notes' }, daily_template = 'x' })
    assert.are.same({ '~/notes' }, opts.roam_dirs)
    assert.are.equal('x', opts.daily_template)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ roam_dirs = { '/tmp' } })
    assert.are.same({}, config.defaults.roam_dirs)
  end)
end)

local config = require('mep.snippet.config')

describe('mep.snippet.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.tab_keymap)
    assert.is_true(config.defaults.builtin_langs)
    assert.are.same({ '<leader>yy' }, config.defaults.keymaps.picker)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides tab_keymap', function()
    local opts = config.setup({ tab_keymap = false })
    assert.is_false(opts.tab_keymap)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ tab_keymap = false })
    assert.is_true(config.defaults.tab_keymap)
  end)
end)

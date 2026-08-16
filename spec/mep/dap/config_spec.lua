local config = require('mep.dap.config')

describe('mep.dap.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.adapters)
    assert.are.equal('●', config.defaults.signs.breakpoint.text)
    assert.are.equal('▶', config.defaults.signs.stopped.text)
    assert.are.same({ '<leader>db' }, config.defaults.keymaps.toggle_breakpoint)
    assert.are.same({ '<leader>dc' }, config.defaults.keymaps.continue)
    assert.are.equal('left', config.defaults.sidebar.position)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('merges an adapter override on top of the (empty) default table', function()
    local opts = config.setup({ adapters = { debugpy = { cmd = { 'custom-debugpy' } } } })
    assert.are.same({ cmd = { 'custom-debugpy' } }, opts.adapters.debugpy)
  end)

  it('deep-merges a partial keymap override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { continue = { '<F5>' } } })
    assert.are.same({ '<F5>' }, opts.keymaps.continue)
    assert.are.same(config.defaults.keymaps.step_over, opts.keymaps.step_over)
  end)

  it('overrides sidebar options independently', function()
    local opts = config.setup({ sidebar = { position = 'left' } })
    assert.are.equal('left', opts.sidebar.position)
    assert.are.equal(config.defaults.sidebar.width, opts.sidebar.width)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ signs = { breakpoint = { text = 'X', hl = 'Error' } } })
    assert.are.equal('●', config.defaults.signs.breakpoint.text)
  end)
end)

local config = require('mep.repl.config')

describe('mep.repl.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal('filetype', config.defaults.scope)
    assert.are.same({}, config.defaults.commands)
    assert.are.equal(0.3, config.defaults.terminal_height_ratio)
    assert.are.same({ '<leader>sl' }, config.defaults.keymaps.send_line)
    assert.are.same({ '<leader>ss' }, config.defaults.keymaps.send_selection)
    assert.are.same({ '<leader>sb' }, config.defaults.keymaps.send_buffer)
    assert.are.same({ '<leader>sr' }, config.defaults.keymaps.jump_to_repl)
    assert.are.same({ '<leader>sc' }, config.defaults.keymaps.jump_back)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides scope/commands independently', function()
    local opts = config.setup({ scope = 'buffer', commands = { python = { 'ipython' } } })
    assert.are.equal('buffer', opts.scope)
    assert.are.same({ python = { 'ipython' } }, opts.commands)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ scope = 'buffer' })
    assert.are.equal('filetype', config.defaults.scope)
  end)
end)

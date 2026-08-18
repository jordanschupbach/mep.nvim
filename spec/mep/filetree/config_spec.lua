local config = require('mep.filetree.config')

describe('mep.filetree.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal(30, config.defaults.width)
    assert.is_nil(config.defaults.root)
    assert.is_false(config.defaults.show_hidden)
    assert.is_false(config.defaults.show_gitignored)
    assert.are.same({ '<CR>', 'o' }, config.defaults.keymaps.open)
    assert.are.same({ 'a' }, config.defaults.keymaps.add)
    assert.are.same({ 'r' }, config.defaults.keymaps.rename)
    assert.are.same({ 'd' }, config.defaults.keymaps.delete)
    assert.are.same({ '?' }, config.defaults.keymaps.help)
    assert.are.same({ '<C-o>' }, config.defaults.keymaps.open_system)
    assert.are.same({ 'H' }, config.defaults.keymaps.toggle_hidden)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('deep-merges a partial override, preserving sibling keymap defaults', function()
    local opts = config.setup({ keymaps = { close = { '<C-q>' } } })
    assert.are.same({ '<C-q>' }, opts.keymaps.close)
    assert.are.same(config.defaults.keymaps.open, opts.keymaps.open)
  end)

  it('overrides width/root/show_hidden independently', function()
    local opts = config.setup({ width = 40, show_hidden = true })
    assert.are.equal(40, opts.width)
    assert.is_true(opts.show_hidden)
    assert.is_nil(opts.root)
  end)

  it('overrides show_gitignored independently', function()
    local opts = config.setup({ show_gitignored = true })
    assert.is_true(opts.show_gitignored)
    assert.is_false(opts.show_hidden)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ width = 999 })
    assert.are.equal(30, config.defaults.width)
  end)
end)

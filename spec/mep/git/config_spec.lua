local config = require('mep.git.config')

describe('mep.git.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.enable)
    assert.are.equal(200, config.defaults.debounce_ms)
    assert.are.equal('HEAD', config.defaults.base)
    assert.are.same({ '|', 'MepGitAdd' }, { config.defaults.signs.add.text, config.defaults.signs.add.hl })
    assert.are.same({ ']c', ']g' }, config.defaults.keymaps.next_hunk)
    assert.are.same({ '[c', '[g' }, config.defaults.keymaps.prev_hunk)
    assert.are.same({ '<leader>gg' }, config.defaults.keymaps.toggle_sidebar)
    assert.are.same({ '<leader>gG' }, config.defaults.keymaps.toggle_sidebar_dock)
    assert.are.equal('right', config.defaults.sidebar.position)
    assert.are.same({ 'c' }, config.defaults.sidebar.keymaps.commit)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('overrides debounce_ms independently of signs', function()
    local opts = config.setup({ debounce_ms = 50 })
    assert.are.equal(50, opts.debounce_ms)
    assert.are.same(config.defaults.signs, opts.signs)
  end)

  it('deep-merges nested sidebar keymaps rather than replacing the table', function()
    local opts = config.setup({ sidebar = { keymaps = { commit = { 'C' } } } })
    assert.are.same({ 'C' }, opts.sidebar.keymaps.commit)
    assert.are.same(config.defaults.sidebar.keymaps.refresh, opts.sidebar.keymaps.refresh)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ enable = false })
    assert.is_true(config.defaults.enable)
  end)
end)

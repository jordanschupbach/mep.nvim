local config = require('mep.treesitter.config')

describe('mep.treesitter.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.highlight)
    assert.is_false(config.defaults.fold)
    assert.is_true(config.defaults.ensure_installed)
  end)

  it('defaults install_dir to a parser/ subdir under an already-on-runtimepath location', function()
    assert.matches('/site/parser$', config.defaults.install_dir)
    assert.are.equal(vim.fn.stdpath('data') .. '/site/parser', config.defaults.install_dir)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides ensure_installed with a curated subset list', function()
    local opts = config.setup({ ensure_installed = { 'lua', 'python' } })
    assert.are.same({ 'lua', 'python' }, opts.ensure_installed)
  end)

  it('overrides fold and highlight independently', function()
    local opts = config.setup({ fold = true, highlight = false })
    assert.is_true(opts.fold)
    assert.is_false(opts.highlight)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ ensure_installed = false })
    assert.is_true(config.defaults.ensure_installed)
  end)
end)

local config = require('mep.lsp.config')

describe('mep.lsp.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.enable)
    assert.are.same({}, config.defaults.servers)
    assert.is_true(config.defaults.diagnostics.virtual_text)
    assert.are.equal('rounded', config.defaults.diagnostics.float.border)
    assert.is_true(config.defaults.completion)
    assert.are.same({ 'gd' }, config.defaults.keymaps.goto_definition)
    assert.are.same({ 'gD' }, config.defaults.keymaps.goto_declaration)
    assert.are.same({ 'gr' }, config.defaults.keymaps.references)
    assert.are.same({ 'gi' }, config.defaults.keymaps.implementation)
    assert.are.same({ 'K' }, config.defaults.keymaps.hover)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('accepts enable as a list of server names', function()
    local opts = config.setup({ enable = { 'lua_ls' } })
    assert.are.same({ 'lua_ls' }, opts.enable)
  end)

  it('accepts enable = false', function()
    local opts = config.setup({ enable = false })
    assert.is_false(opts.enable)
  end)

  it('deep-merges a nested keymaps override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { hover = { '<leader>k' } } })
    assert.are.same({ '<leader>k' }, opts.keymaps.hover)
    assert.are.same({ 'gd' }, opts.keymaps.goto_definition)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ completion = false })
    assert.is_true(config.defaults.completion)
  end)
end)

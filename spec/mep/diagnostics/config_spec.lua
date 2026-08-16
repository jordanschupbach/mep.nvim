local config = require('mep.diagnostics.config')

describe('mep.diagnostics.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.enable)
    assert.are.equal('●', config.defaults.circle)
    assert.are.equal('DiagnosticError', config.defaults.hl[vim.diagnostic.severity.ERROR])
    assert.are.equal('DiagnosticWarn', config.defaults.hl[vim.diagnostic.severity.WARN])
    assert.are.equal('DiagnosticInfo', config.defaults.hl[vim.diagnostic.severity.INFO])
    assert.are.equal('DiagnosticHint', config.defaults.hl[vim.diagnostic.severity.HINT])
    assert.are.equal('rounded', config.defaults.float.border)
    assert.are.same({ '<leader>ld' }, config.defaults.keymaps.show_line)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a partial keymap override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { show_line = { '<F3>' } } })
    assert.are.same({ '<F3>' }, opts.keymaps.show_line)
    assert.are.equal(config.defaults.circle, opts.circle)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ enable = false })
    assert.is_true(config.defaults.enable)
  end)
end)

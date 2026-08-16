local config = require('mep.docs.config')

describe('mep.docs.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.doc_hints)
    assert.are.same({ '<leader>ld' }, config.defaults.keymaps.generate)
    assert.are.same({ '<leader>lD' }, config.defaults.keymaps.lookup)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('merges a doc_hints override on top of the (empty) default table', function()
    local opts = config.setup({ doc_hints = { python = 'python~3.9' } })
    assert.are.same({ python = 'python~3.9' }, opts.doc_hints)
  end)

  it('deep-merges a partial keymap override, preserving the sibling default', function()
    local opts = config.setup({ keymaps = { generate = { '<F2>' } } })
    assert.are.same({ '<F2>' }, opts.keymaps.generate)
    assert.are.same(config.defaults.keymaps.lookup, opts.keymaps.lookup)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ doc_hints = { python = 'x' } })
    assert.are.same({}, config.defaults.doc_hints)
  end)
end)

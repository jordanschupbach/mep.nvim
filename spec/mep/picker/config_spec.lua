local config = require('mep.picker.config')

describe('mep.picker.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.equal(20, config.defaults.debounce_ms.static)
    assert.are.equal(120, config.defaults.debounce_ms.dynamic)
    assert.are.same({ '<CR>' }, config.defaults.keymaps.select)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('deep-merges a partial override, preserving sibling defaults', function()
    local opts = config.setup({ debounce_ms = { static = 5 } })
    assert.are.equal(5, opts.debounce_ms.static)
    assert.are.equal(120, opts.debounce_ms.dynamic) -- untouched default
  end)

  it('overrides a keymap action wholesale, leaving other actions at their default', function()
    local opts = config.setup({ keymaps = { select = { '<C-y>' } } })
    assert.are.same({ '<C-y>' }, opts.keymaps.select)
    assert.are.same(config.defaults.keymaps.close, opts.keymaps.close)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ debounce_ms = { static = 999 } })
    assert.are.equal(20, config.defaults.debounce_ms.static)
  end)
end)

local config = require('mep.bib.config')

describe('mep.bib.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({ '<localleader>ir' }, config.defaults.keymaps.insert)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a partial keymap override', function()
    local opts = config.setup({ keymaps = { insert = { '<F4>' } } })
    assert.are.same({ '<F4>' }, opts.keymaps.insert)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ keymaps = { insert = { '<F4>' } } })
    assert.are.same({ '<localleader>ir' }, config.defaults.keymaps.insert)
  end)
end)

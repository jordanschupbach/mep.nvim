local config = require('mep.flashcards.config')

describe('mep.flashcards.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.are.same({}, config.defaults.drill_files)
    assert.are.equal('drill', config.defaults.tag)
    assert.are.same({ '<leader>fr' }, config.defaults.keymaps.review)
  end)

  it('setup({}) returns a copy of the defaults', function()
    local opts = config.setup({})
    assert.are.same(config.defaults, opts)
  end)

  it('overrides drill_files/tag independently', function()
    local opts = config.setup({ drill_files = { '~/notes/*.org' }, tag = 'flashcard' })
    assert.are.same({ '~/notes/*.org' }, opts.drill_files)
    assert.are.equal('flashcard', opts.tag)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ tag = 'x' })
    assert.are.equal('drill', config.defaults.tag)
  end)
end)

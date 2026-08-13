local config = require('mep.project.config')

describe('mep.project.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_nil(config.defaults.persist_path)
    assert.are.same({ 'README.org', 'README.md' }, config.defaults.readme_names)
    assert.is_true(config.defaults.open_filetree)
    assert.is_true(config.defaults.open_terminal)
    assert.are.equal(0.3, config.defaults.terminal_height_ratio)
    assert.are.same({ '<C-a>' }, config.defaults.keymaps.add)
  end)

  it('setup({}) returns a copy of the defaults', function()
    assert.are.same(config.defaults, config.setup({}))
  end)

  it('deep-merges a nested override, preserving sibling defaults', function()
    local opts = config.setup({ keymaps = { add = { '<leader>pa' } } })
    assert.are.same({ '<leader>pa' }, opts.keymaps.add)
    assert.are.same({ 'README.org', 'README.md' }, opts.readme_names)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ readme_names = { 'readme.txt' } })
    assert.are.same({ 'README.org', 'README.md' }, config.defaults.readme_names)
  end)

  it('setup(nil) resets to the defaults', function()
    config.setup({ persist_path = '/tmp/x.json' })
    config.setup(nil)
    assert.is_nil(config.options.persist_path)
  end)
end)

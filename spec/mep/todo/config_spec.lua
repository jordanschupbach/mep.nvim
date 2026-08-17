local config = require('mep.todo.config')

describe('mep.todo.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('defaults file to the project-relative TODO.org', function()
    assert.are.equal('TODO.org', config.defaults.file)
  end)

  it('defaults keymaps.toggle to <leader>tt', function()
    assert.are.same({ '<leader>tt' }, config.defaults.keymaps.toggle)
  end)

  it('has its own independent panel sizing', function()
    assert.are.equal('right', config.defaults.panel.position)
    assert.are.equal(42, config.defaults.panel.width)
    assert.is_true(config.defaults.panel.float)
    assert.are.equal('rounded', config.defaults.panel.border)
  end)

  it('setup deep-merges onto a fresh copy of the defaults', function()
    config.setup({ file = '~/notes/todo.org' })
    assert.are.equal('~/notes/todo.org', config.options.file)
    assert.are.same({ '<leader>tt' }, config.options.keymaps.toggle)
  end)
end)

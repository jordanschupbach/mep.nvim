local sanity = require('mep.sanity.sanity')
local sanity_config = require('mep.sanity.config')

-- Neovim normalizes a keymap's lhs display form when storing/reporting
-- it back — a Ctrl+letter's case (`<C-t>` -> `<C-T>`), and `<A-...>`
-- (Alt) to the `<M-...>` (Meta) spelling it's a synonym of — so compare
-- by the actual termcodes instead of the display string.
local function has_map(lhs)
  local target = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == target then
      return true
    end
  end
  return false
end

describe('mep.sanity.sanity', function()
  local saved_leader, saved_localleader, saved_options, saved_number, saved_signcolumn

  before_each(function()
    saved_leader = vim.g.mapleader
    saved_localleader = vim.g.maplocalleader
    saved_options = vim.deepcopy(sanity_config.options)
    saved_number = vim.o.number
    saved_signcolumn = vim.o.signcolumn
  end)

  after_each(function()
    vim.g.mapleader = saved_leader
    vim.g.maplocalleader = saved_localleader
    sanity_config.options = saved_options
    vim.o.number = saved_number
    vim.o.signcolumn = saved_signcolumn
    for _, lhs in ipairs({ '<C-t>', '<A-1>', '<A-2>', '<A-3>', '<A-4>', '<A-5>', '<A-6>', '<A-7>', '<A-8>', '<A-9>' }) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  it('setup({}) applies the default leader (space)', function()
    sanity.setup({})
    assert.are.equal(' ', vim.g.mapleader)
  end)

  it('setup(opts) overrides the leader', function()
    sanity.setup({ leader = ',' })
    assert.are.equal(',', vim.g.mapleader)
  end)

  it('setup({ leader = false }) does not touch an existing mapleader', function()
    vim.g.mapleader = 'sentinel'
    sanity.setup({ leader = false })
    assert.are.equal('sentinel', vim.g.mapleader)
  end)

  it('returns the merged options table', function()
    local options = sanity.setup({ leader = ';' })
    assert.are.equal(';', options.leader)
  end)

  it('exposes the leader submodule', function()
    assert.are.equal(require('mep.sanity.leader'), sanity.leader)
  end)

  it('exposes the tabs submodule', function()
    assert.are.equal(require('mep.sanity.tabs'), sanity.tabs)
  end)

  it('exposes the gutter submodule', function()
    assert.are.equal(require('mep.sanity.gutter'), sanity.gutter)
  end)

  it('setup({}) turns number on and signcolumn to "yes"', function()
    vim.o.number = false
    vim.o.signcolumn = 'auto'
    sanity.setup({})
    assert.is_true(vim.o.number)
    assert.are.equal('yes', vim.o.signcolumn)
  end)

  it('setup({ number = false, signcolumn = false }) leaves both untouched', function()
    vim.o.number = false
    vim.o.signcolumn = 'auto'
    sanity.setup({ number = false, signcolumn = false })
    assert.is_false(vim.o.number)
    assert.are.equal('auto', vim.o.signcolumn)
  end)

  it('setup({}) binds the default tab keymaps', function()
    sanity.setup({})
    assert.is_true(has_map('<C-t>'))
    assert.is_true(has_map('<A-1>'))
    assert.is_true(has_map('<A-9>'))
  end)

  it('setup(opts) overrides the tab keymaps', function()
    sanity.setup({ tabs = { keymaps = { new = { '<F13>' }, select = {} } } })
    assert.is_true(has_map('<F13>'))
    assert.is_false(has_map('<C-t>'))
    assert.is_false(has_map('<A-1>'))
    pcall(vim.keymap.del, 'n', '<F13>')
  end)

  it('setup({ tabs = { keymaps = false } }) binds no tab keymaps', function()
    sanity.setup({ tabs = { keymaps = false } })
    assert.is_false(has_map('<C-t>'))
    assert.is_false(has_map('<A-1>'))
    assert.is_false(has_map('<A-9>'))
  end)
end)

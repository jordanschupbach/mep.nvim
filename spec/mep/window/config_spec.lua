local config = require('mep.window.config')
local keys = require('mep.core.keys')

describe('mep.window.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has sensible defaults', function()
    assert.is_true(config.defaults.manual.enable)
    assert.are.equal(3, config.defaults.manual.resize_step)
    assert.are.same({ '<Mod1-v>' }, config.defaults.manual.keymaps.split_vertical)
    assert.are.same({ '<Mod1-s>' }, config.defaults.manual.keymaps.split_horizontal)
    assert.are.same({ '<Mod1-h>' }, config.defaults.manual.keymaps.focus_left)
    assert.are.same({ '<Mod1-S-h>' }, config.defaults.manual.keymaps.resize_left)
    assert.are.same({ '<Mod1-C-h>' }, config.defaults.manual.keymaps.move_left)
    assert.are.same({ '<Mod1-n>', '<Mod1-Tab>' }, config.defaults.manual.keymaps.next_tab)
    assert.are.same({ '<Mod1-p>', '<Mod1-S-Tab>' }, config.defaults.manual.keymaps.prev_tab)
    assert.are.same({ '<Mod1-d>' }, config.defaults.manual.keymaps.remove)
    assert.are.equal(0.55, config.defaults.auto.mfact)
    assert.are.equal(1, config.defaults.auto.nmaster)
  end)

  it('every auto layout has an (empty by default) keymap list', function()
    local auto = require('mep.window.auto')
    for _, name in ipairs(auto.names) do
      assert.are.same({}, config.defaults.auto.keymaps[name], name .. ' should default unbound')
    end
  end)

  it('setup({}) returns a copy of the defaults with <Mod1-...> expanded', function()
    local expanded = keys.expand_table(vim.deepcopy(config.defaults))
    assert.are.same(expanded, config.setup({}))
    assert.is_nil(config.setup({}).manual.keymaps.split_vertical[1]:find('Mod1'))
  end)

  it('overrides manual.resize_step independently of its keymaps', function()
    local opts = config.setup({ manual = { resize_step = 10 } })
    assert.are.equal(10, opts.manual.resize_step)
    assert.are.same(keys.expand_table(vim.deepcopy(config.defaults.manual.keymaps)), opts.manual.keymaps)
  end)

  it('deep-merges a single auto keymap without clobbering the others', function()
    local opts = config.setup({ auto = { keymaps = { square = { '<leader>wq' } } } })
    assert.are.same({ '<leader>wq' }, opts.auto.keymaps.square)
    assert.are.same({}, opts.auto.keymaps.spiral)
  end)

  it('does not mutate the stored defaults table', function()
    config.setup({ manual = { enable = false } })
    assert.is_true(config.defaults.manual.enable)
  end)
end)

-- Exercises mep.window.setup()'s own wiring (config -> panes enable/
-- disable, auto.keymaps -> mep.window.auto.apply); the pieces
-- themselves are covered by config_spec/auto_spec/panes_spec.
local window = require('mep.window')
local config = require('mep.window.config')
local panes = require('mep.window.panes')
local auto = require('mep.window.auto')

describe('mep.window', function()
  local saved_config

  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  before_each(function()
    saved_config = vim.deepcopy(config.options)
  end)

  after_each(function()
    panes._reset()
    config.options = saved_config
    for _, lhs in ipairs({ '<F5>', '<F6>' }) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    -- setup() may have bound the (default-unbound) auto keymaps this
    -- test configured — clean those up too, the same reasoning as mep.
    -- git's own git_spec.lua after_each (an unbound-global-keymap leak
    -- otherwise outlives this file, into whichever spec runs next).
    for _, name in ipairs(auto.names) do
      for _, lhs in ipairs(config.defaults.auto.keymaps[name] or {}) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
  end)

  it('exposes the panes/auto submodules', function()
    assert.are.equal(panes, window.panes)
    assert.are.equal(auto, window.auto)
  end)

  it('setup() returns the resolved config', function()
    local opts = window.setup({ manual = { resize_step = 7 } })
    assert.are.equal(7, opts.manual.resize_step)
  end)

  it('setup() enables manual-layout keymaps by default', function()
    vim.cmd('tabnew')
    window.setup({ manual = { keymaps = { split_vertical = { '<F5>' } } } })
    local win1 = vim.api.nvim_get_current_win()
    feed('<F5>')
    assert.are_not.equal(win1, vim.api.nvim_get_current_win())
    vim.cmd('tabclose!')
  end)

  it('setup({ manual = { enable = false } }) does not bind manual keymaps', function()
    vim.cmd('tabnew')
    window.setup({ manual = { enable = false, keymaps = { split_vertical = { '<F5>' } } } })
    local win1 = vim.api.nvim_get_current_win()
    feed('<F5>')
    assert.are.equal(win1, vim.api.nvim_get_current_win())
    vim.cmd('tabclose!')
  end)

  it('binds any configured auto-layout keymap to auto.apply', function()
    window.setup({ auto = { keymaps = { square = { '<F6>' } } } })
    local orig_apply = auto.apply
    local seen
    auto.apply = function(name)
      seen = name
    end
    feed('<F6>')
    auto.apply = orig_apply
    assert.are.equal('square', seen)
  end)
end)

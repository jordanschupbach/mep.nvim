local keymaps = require('mep.picker.keymaps')
local picker = require('mep.picker.picker')

-- See spec/mep/sanity/tabs_spec.lua: Neovim normalizes a keymap's lhs
-- display form when reporting it back, so compare by termcodes.
local function has_map(lhs)
  local target = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == target then
      return true
    end
  end
  return false
end

describe('mep.picker.keymaps', function()
  local bound

  before_each(function()
    bound = {}
  end)

  after_each(function()
    for _, lhs in ipairs(bound) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  it('binds buffer_search to the given lhs', function()
    bound = { '<F13>' }
    keymaps.apply({ buffer_search = { '<F13>' } })
    assert.is_true(has_map('<F13>'))
  end)

  it('binds every lhs in a multi-entry buffer_search list', function()
    bound = { '<F13>', '<F14>' }
    keymaps.apply({ buffer_search = { '<F13>', '<F14>' } })
    assert.is_true(has_map('<F13>'))
    assert.is_true(has_map('<F14>'))
  end)

  it('leaves buffer_search unbound when its list is empty', function()
    assert.has_no.errors(function()
      keymaps.apply({ buffer_search = {} })
    end)
  end)

  it('does nothing when passed false', function()
    assert.has_no.errors(function()
      keymaps.apply(false)
    end)
  end)

  it('does nothing when passed nil', function()
    assert.has_no.errors(function()
      keymaps.apply(nil)
    end)
  end)

  it('a bound key calls mep.picker.buffer_search()', function()
    bound = { '<F13>' }
    local original = picker.buffer_search
    local called = false
    picker.buffer_search = function()
      called = true
    end

    keymaps.apply({ buffer_search = { '<F13>' } })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<F13>', true, false, true), 'x', false)

    picker.buffer_search = original
    assert.is_true(called)
  end)
end)

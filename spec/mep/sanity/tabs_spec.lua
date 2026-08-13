local tabs = require('mep.sanity.tabs')

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

describe('mep.sanity.tabs', function()
  local bound

  before_each(function()
    bound = {}
  end)

  after_each(function()
    for _, lhs in ipairs(bound) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  it('binds new to :tabnew', function()
    bound = { '<F13>' }
    tabs.apply({ new = { '<F13>' } })
    assert.is_true(has_map('<F13>'))
  end)

  it('binds every lhs in a multi-entry new list', function()
    bound = { '<F13>', '<F16>' }
    tabs.apply({ new = { '<F13>', '<F16>' } })
    assert.is_true(has_map('<F13>'))
    assert.is_true(has_map('<F16>'))
  end)

  it('binds select positionally, each lhs jumping to its own index', function()
    bound = { '<F13>', '<F14>', '<F15>' }
    tabs.apply({ select = { '<F13>', '<F14>', '<F15>' } })
    assert.is_true(has_map('<F13>'))
    assert.is_true(has_map('<F14>'))
    assert.is_true(has_map('<F15>'))
  end)

  it('leaves an action unbound when its list is empty', function()
    assert.has_no.errors(function()
      tabs.apply({ new = {}, select = {} })
    end)
  end)

  it('does nothing when passed false', function()
    assert.has_no.errors(function()
      tabs.apply(false)
    end)
  end)

  it('does nothing when passed nil', function()
    assert.has_no.errors(function()
      tabs.apply(nil)
    end)
  end)

  it('a bound new key actually opens a new tab', function()
    bound = { '<F13>' }
    tabs.apply({ new = { '<F13>' } })
    local before = #vim.api.nvim_list_tabpages()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<F13>', true, false, true), 'x', false)
    assert.are.equal(before + 1, #vim.api.nvim_list_tabpages())
    vim.cmd('tabclose')
  end)

  it('a bound select key jumps straight to that tab number', function()
    bound = { '<F13>', '<F14>', '<F15>' }
    tabs.apply({ select = { '<F13>', '<F14>', '<F15>' } })
    local original_count = #vim.api.nvim_list_tabpages()
    vim.cmd('tabnew')
    vim.cmd('tabnew') -- at least 3 tabs now; tab 1 and 3 are absolute positions

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<F13>', true, false, true), 'x', false)
    assert.are.equal(1, vim.fn.tabpagenr())
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<F15>', true, false, true), 'x', false)
    assert.are.equal(3, vim.fn.tabpagenr())

    while #vim.api.nvim_list_tabpages() > original_count do
      vim.cmd('tabclose')
    end
  end)
end)

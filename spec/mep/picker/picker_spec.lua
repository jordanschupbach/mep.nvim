local picker = require('mep.picker.picker')
local config = require('mep.picker.config')

local function has_map(lhs)
  local target = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == target then
      return true
    end
  end
  return false
end

describe('mep.picker.picker', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
    pcall(vim.keymap.del, 'n', '<F13>')
  end)

  it('setup() applies configured trigger keymaps', function()
    picker.setup({ triggers = { buffer_search = { '<F13>' } } })
    assert.is_true(has_map('<F13>'))
  end)

  it('setup() returns the resolved options', function()
    local opts = picker.setup({})
    assert.are.same(config.defaults, opts)
  end)
end)

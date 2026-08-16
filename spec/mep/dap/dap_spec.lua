local dap = require('mep.dap')
local session = require('mep.dap.session')
local sidebar = require('mep.dap.sidebar')
local repl = require('mep.dap.repl')
local breakpoints = require('mep.dap.breakpoints')

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.dap', function()
  after_each(function()
    session._reset()
    sidebar._reset()
    repl._reset()
    breakpoints.clear_all()
  end)

  it('re-exports its submodules', function()
    assert.are.equal(session, dap.session)
    assert.are.equal(sidebar, dap.sidebar)
    assert.are.equal(repl, dap.repl)
    assert.are.equal(breakpoints, dap.breakpoints)
    assert.is_not_nil(dap.adapters)
  end)

  it('setup() returns the resolved config and binds its keymaps', function()
    local keymaps = {
      toggle_breakpoint = { '<localleader>db1' },
      continue = { '<localleader>dc1' },
      step_over = {},
      step_into = {},
      step_out = {},
      launch = {},
      terminate = {},
      toggle_sidebar = {},
      toggle_repl = {},
      evaluate = {},
    }
    local options = dap.setup({ keymaps = keymaps })
    assert.are.same(keymaps.toggle_breakpoint, options.keymaps.toggle_breakpoint)
    assert.is_not_nil(next(vim.fn.maparg('<localleader>db1', 'n', false, true)))
    assert.is_not_nil(next(vim.fn.maparg('<localleader>dc1', 'n', false, true)))
    del_all(keymaps.toggle_breakpoint)
    del_all(keymaps.continue)
  end)

  it('works with sensible defaults even without an explicit setup() call', function()
    assert.are.equal('inactive', session.status)
    assert.are.same({}, breakpoints.list(vim.api.nvim_get_current_buf()))
  end)
end)

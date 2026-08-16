local keymaps = require('mep.dap.keymaps')
local breakpoints = require('mep.dap.breakpoints')
local session = require('mep.dap.session')
local sidebar = require('mep.dap.sidebar')
local repl = require('mep.dap.repl')

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.dap.keymaps', function()
  local bound

  after_each(function()
    if bound then
      for _, lhs_list in pairs(bound) do
        del_all(lhs_list)
      end
    end
    session._reset()
    sidebar._reset()
    repl._reset()
    breakpoints.clear_all()
  end)

  it('binds every configured action to its keymap', function()
    bound = {
      toggle_breakpoint = { '<localleader>tb' },
      continue = { '<localleader>tc' },
      step_over = { '<localleader>tn' },
      step_into = { '<localleader>ti' },
      step_out = { '<localleader>to' },
      launch = { '<localleader>tl' },
      terminate = { '<localleader>tq' },
      toggle_sidebar = { '<localleader>tu' },
      toggle_repl = { '<localleader>tr' },
      evaluate = { '<localleader>te' },
    }
    keymaps.bind(bound)
    for _, lhs_list in pairs(bound) do
      for _, lhs in ipairs(lhs_list) do
        assert.is_not_nil(next(vim.fn.maparg(lhs, 'n', false, true)), lhs .. ' should be bound')
      end
    end
  end)

  it('toggle_breakpoint acts on the current buffer/line at press time', function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, '/tmp/mep-dap-keymaps-' .. buf .. '.py')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b', 'c' })
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    bound = { toggle_breakpoint = { '<localleader>tb2' } }
    keymaps.bind(bound)
    vim.cmd('normal ' .. vim.api.nvim_replace_termcodes('<localleader>tb2', true, false, true))

    assert.are.same({ 2 }, breakpoints.list(buf))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

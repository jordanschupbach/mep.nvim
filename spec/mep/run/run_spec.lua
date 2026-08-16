local run = require('mep.run')
local runner = require('mep.run.runner')
local terminal = require('mep.run.terminal')

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.run', function()
  it('re-exports runner/terminal', function()
    assert.are.equal(runner, run.runner)
    assert.are.equal(terminal, run.terminal)
  end)

  describe('run_current_file', function()
    it('opens a terminal with the resolved command', function()
      local orig_command = runner.command
      local seen_bufnr
      runner.command = function(bufnr)
        seen_bufnr = bufnr
        return { 'echo', 'hi' }
      end
      local orig_open = terminal.open
      local seen_cmd
      terminal.open = function(cmd)
        seen_cmd = cmd
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      run.run_current_file()

      runner.command = orig_command
      terminal.open = orig_open

      assert.are.equal(buf, seen_bufnr)
      assert.are.same({ 'echo', 'hi' }, seen_cmd)
    end)

    it('notifies (opens nothing) when the command cannot be resolved', function()
      local orig_command = runner.command
      runner.command = function()
        return nil, 'mep.run: boom'
      end
      local orig_open = terminal.open
      local opened = false
      terminal.open = function()
        opened = true
      end

      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end

      run.run_current_file()

      vim.notify = orig_notify
      runner.command = orig_command
      terminal.open = orig_open

      assert.is_false(opened)
      assert.are.equal('mep.run: boom', notified)
    end)
  end)

  describe('widget', function()
    it('returns a mep.chrome-widget-shaped table', function()
      local w = run.widget()
      assert.is_string(w.text)
      assert.is_function(w.on_click)
    end)

    it('on_click runs the current file', function()
      local orig_run = run.run_current_file
      local called = false
      run.run_current_file = function()
        called = true
      end
      run.widget().on_click()
      run.run_current_file = orig_run
      assert.is_true(called)
    end)
  end)

  describe('setup', function()
    it('binds the configured run keymap', function()
      local keymaps = { run = { '<localleader>xr1' } }
      run.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>xr1', 'n', false, true)))
      del_all(keymaps.run)
    end)

    it('returns the resolved options', function()
      local options = run.setup({ terminal_height_ratio = 0.5, keymaps = { run = {} } })
      assert.are.equal(0.5, options.terminal_height_ratio)
    end)
  end)
end)

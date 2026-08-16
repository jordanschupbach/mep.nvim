local repl = require('mep.dap.repl')
local session = require('mep.dap.session')
local client_mod = require('mep.dap.client')

describe('mep.dap.repl', function()
  after_each(function()
    repl._reset()
    session._reset()
  end)

  describe('append', function()
    it('replaces the initial empty buffer line with the first append', function()
      repl.append('hello')
      repl.open()
      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ 'hello' }, lines)
    end)

    it('appends subsequent calls as new lines', function()
      repl.append('one')
      repl.append('two')
      repl.open()
      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ 'one', 'two' }, lines)
    end)

    it('splits embedded newlines into separate lines', function()
      repl.append('a\nb\nc')
      repl.open()
      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ 'a', 'b', 'c' }, lines)
    end)
  end)

  describe('open/close/toggle', function()
    it('open shows the console, close/toggle hide it', function()
      repl.open()
      assert.is_true(repl.is_open())
      repl.close()
      assert.is_false(repl.is_open())
      repl.toggle()
      assert.is_true(repl.is_open())
      repl.toggle()
      assert.is_false(repl.is_open())
    end)

    it('reuses the same buffer across open/close cycles', function()
      repl.open()
      local buf1 = repl.panel_buf()
      repl.close()
      repl.open()
      assert.are.equal(buf1, repl.panel_buf())
    end)
  end)

  describe('session output', function()
    -- mep.dap.repl subscribes to mep.dap.session (on its first open())
    -- and appends 'output' event bodies — drive a real 'output' event
    -- the same way mep.dap.session_spec.lua does, via a stubbed
    -- mep.dap.client.new so mep.dap.session's own on_event dispatch runs
    -- for real (this is what actually exercises the subscription, not a
    -- hand-rolled substitute for it).
    local orig_new, orig_executable, last_opts

    before_each(function()
      orig_new = client_mod.new
      orig_executable = vim.fn.executable
      vim.fn.executable = function()
        return 1
      end
      client_mod.new = function(opts)
        last_opts = opts
        return { request = function() end, is_running = function() return true end, close = function() end }
      end
    end)

    after_each(function()
      client_mod.new = orig_new
      vim.fn.executable = orig_executable
    end)

    it('appends adapter output events to the console', function()
      repl.open()
      session.launch('debugpy', {})
      last_opts.on_event('output', { category = 'stdout', output = 'hello world' })

      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ 'hello world' }, lines)
    end)

    it('appends a session-ended marker on terminated', function()
      repl.open()
      session.launch('debugpy', {})
      last_opts.on_event('terminated', nil)

      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ '[session ended]' }, lines)
    end)
  end)

  describe('evaluate_interactive', function()
    it('prompts, sends the expression, and appends both it and the result', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('1 + 1')
      end

      local orig_evaluate = session.evaluate
      local sent_expr
      session.evaluate = function(expression, cb)
        sent_expr = expression
        cb({ success = true, body = { result = '2' } })
      end

      repl.evaluate_interactive()

      vim.ui.input = orig_input
      session.evaluate = orig_evaluate

      assert.are.equal('1 + 1', sent_expr)
      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ '> 1 + 1', '2' }, lines)
    end)

    it('appends an error line when evaluation fails', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('bogus')
      end
      local orig_evaluate = session.evaluate
      session.evaluate = function(_, cb)
        cb({ success = false, message = 'name error' })
      end

      repl.evaluate_interactive()

      vim.ui.input = orig_input
      session.evaluate = orig_evaluate

      local lines = vim.api.nvim_buf_get_lines(repl.panel_buf(), 0, -1, false)
      assert.are.same({ '> bogus', 'error: name error' }, lines)
    end)

    it('does nothing when the prompt is cancelled or left empty', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      local orig_evaluate = session.evaluate
      local called = false
      session.evaluate = function()
        called = true
      end

      repl.evaluate_interactive()

      vim.ui.input = orig_input
      session.evaluate = orig_evaluate
      assert.is_false(called)
    end)
  end)
end)

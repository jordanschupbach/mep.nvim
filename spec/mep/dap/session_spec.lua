-- mep.dap.session builds on mep.dap.client, which is itself already
-- covered against a mocked vim.fn.jobstart/chansend (client_spec.lua) —
-- here it's mep.dap.client.new that's stubbed (spec/README.md's "stub a
-- module-level dependency" pattern), returning a fake client object that
-- records every request() call and lets the test drive its callback and
-- the adapter's own events (on_event/on_exit) by hand.
local session = require('mep.dap.session')
local client_mod = require('mep.dap.client')
local config = require('mep.dap.config')
local breakpoints = require('mep.dap.breakpoints')

local function make_fake_client()
  local fake = { requests = {}, running = true }
  function fake:request(command, args, callback)
    table.insert(self.requests, { command = command, args = args, callback = callback })
  end
  function fake:is_running()
    return self.running
  end
  function fake:close()
    self.running = false
  end
  return fake
end

local function find_request(fake, command)
  for _, r in ipairs(fake.requests) do
    if r.command == command then
      return r
    end
  end
  return nil
end

describe('mep.dap.session', function()
  local orig_new, orig_executable
  local last_opts, last_client

  before_each(function()
    orig_new = client_mod.new
    orig_executable = vim.fn.executable
    vim.fn.executable = function()
      return 1
    end
    client_mod.new = function(opts)
      last_opts = opts
      last_client = make_fake_client()
      return last_client
    end
  end)

  after_each(function()
    client_mod.new = orig_new
    vim.fn.executable = orig_executable
    session._reset()
    breakpoints.clear_all()
    config.setup({})
  end)

  describe('resolve_adapter', function()
    it('resolves a curated adapter unmodified', function()
      local adapter = session.resolve_adapter('debugpy')
      assert.are.same({ 'python3', '-m', 'debugpy.adapter' }, adapter.cmd)
    end)

    it('merges a config override on top of a curated entry', function()
      config.setup({ adapters = { debugpy = { cmd = { 'custom' } } } })
      local adapter = session.resolve_adapter('debugpy')
      assert.are.same({ 'custom' }, adapter.cmd)
    end)

    it('returns nil for an unknown adapter with no override', function()
      assert.is_nil(session.resolve_adapter('nonexistent'))
    end)

    it('resolves a config-only adapter with no curated entry', function()
      config.setup({ adapters = { my_custom = { cmd = { 'my-adapter' }, filetypes = { 'foo' } } } })
      local adapter = session.resolve_adapter('my_custom')
      assert.are.same({ 'my-adapter' }, adapter.cmd)
    end)
  end)

  describe('launch', function()
    it('spawns the resolved adapter and sends initialize then launch', function()
      session.launch('debugpy', { program = '/tmp/foo.py' })
      assert.are.same({ 'python3', '-m', 'debugpy.adapter' }, last_opts.cmd)

      local init_req = find_request(last_client, 'initialize')
      assert.is_not_nil(init_req)
      assert.are.equal('mep.nvim', init_req.args.clientID)

      init_req.callback({ success = true, body = { supportsConfigurationDoneRequest = true } })
      assert.are.same({ supportsConfigurationDoneRequest = true }, session.capabilities)

      local launch_req = find_request(last_client, 'launch')
      assert.is_not_nil(launch_req)
      assert.are.equal('/tmp/foo.py', launch_req.args.program)
    end)

    it('does not start a second session while one is active', function()
      session.launch('debugpy', {})
      local first_client = last_client
      session.launch('debugpy', {})
      assert.are.equal(first_client, last_client)
    end)

    it('refuses to start when the adapter binary is not on PATH', function()
      vim.fn.executable = function()
        return 0
      end
      session.launch('debugpy', {})
      assert.is_nil(session.client)
    end)

    it('refuses to start for an unknown adapter', function()
      session.launch('nonexistent', {})
      assert.is_nil(session.client)
    end)
  end)

  describe('initialized event -> breakpoints -> configurationDone', function()
    it('sends configurationDone immediately when there are no breakpoints', function()
      session.launch('debugpy', {})
      last_opts.on_event('initialized', nil)
      assert.is_not_nil(find_request(last_client, 'configurationDone'))
      assert.are.equal('running', session.status)
    end)

    it('pushes setBreakpoints for every recorded file before configurationDone', function()
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, '/tmp/mep-dap-session-' .. bufnr .. '.py')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c' })
      breakpoints.toggle(bufnr, 2)

      session.launch('debugpy', {})
      last_opts.on_event('initialized', nil)

      local bp_req = find_request(last_client, 'setBreakpoints')
      assert.is_not_nil(bp_req)
      assert.are.same({ { line = 2 } }, bp_req.args.breakpoints)
      -- configurationDone waits for the setBreakpoints response.
      assert.is_nil(find_request(last_client, 'configurationDone'))

      bp_req.callback({ success = true })
      assert.is_not_nil(find_request(last_client, 'configurationDone'))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('stopped event -> stack/scopes/variables', function()
    it('fetches the stack, top-frame scopes, and their variables', function()
      session.launch('debugpy', {})
      last_opts.on_event('stopped', { threadId = 5, reason = 'breakpoint' })

      assert.are.equal('stopped', session.status)
      assert.are.equal(5, session.current_thread_id)

      local stack_req = find_request(last_client, 'stackTrace')
      assert.is_not_nil(stack_req)
      assert.are.equal(5, stack_req.args.threadId)

      stack_req.callback({
        success = true,
        body = { stackFrames = { { id = 10, name = 'main', line = 3, source = { path = '/tmp/x.py' } } } },
      })
      assert.are.equal(1, #session.stack_frames)
      assert.are.equal(10, session.current_frame_id)

      local scopes_req = find_request(last_client, 'scopes')
      assert.is_not_nil(scopes_req)
      assert.are.equal(10, scopes_req.args.frameId)

      scopes_req.callback({ success = true, body = { scopes = { { name = 'Locals', variablesReference = 100 } } } })
      assert.are.equal(1, #session.scopes)

      local vars_req = find_request(last_client, 'variables')
      assert.is_not_nil(vars_req)
      assert.are.equal(100, vars_req.args.variablesReference)

      vars_req.callback({ success = true, body = { variables = { { name = 'x', value = '1' } } } })
      assert.are.same({ { name = 'x', value = '1' } }, session.variables[100])
    end)

    it('skips a variables request for a scope with variablesReference 0', function()
      session.launch('debugpy', {})
      last_opts.on_event('stopped', { threadId = 1 })
      find_request(last_client, 'stackTrace').callback({
        success = true,
        body = { stackFrames = { { id = 1, name = 'main' } } },
      })
      find_request(last_client, 'scopes').callback({
        success = true,
        body = { scopes = { { name = 'Empty', variablesReference = 0 } } },
      })
      assert.is_nil(find_request(last_client, 'variables'))
    end)
  end)

  describe('subscribe', function()
    it('emits events to every subscriber', function()
      local seen = {}
      session.subscribe(function(kind, data)
        seen[#seen + 1] = { kind = kind, data = data }
      end)
      session.launch('debugpy', {})
      last_opts.on_event('output', { category = 'stdout', output = 'hello\n' })

      local found = false
      for _, e in ipairs(seen) do
        if e.kind == 'output' and e.data.output == 'hello\n' then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('control actions', function()
    local function stopped_session()
      session.launch('debugpy', {})
      last_opts.on_event('stopped', { threadId = 3 })
      return last_client
    end

    it('continue sends a continue request for the current thread', function()
      local client = stopped_session()
      session.continue()
      local req = find_request(client, 'continue')
      assert.is_not_nil(req)
      assert.are.equal(3, req.args.threadId)
    end)

    it('step_over sends next', function()
      local client = stopped_session()
      session.step_over()
      assert.is_not_nil(find_request(client, 'next'))
    end)

    it('step_into sends stepIn', function()
      local client = stopped_session()
      session.step_into()
      assert.is_not_nil(find_request(client, 'stepIn'))
    end)

    it('step_out sends stepOut', function()
      local client = stopped_session()
      session.step_out()
      assert.is_not_nil(find_request(client, 'stepOut'))
    end)

    it('control actions are a no-op with no active thread', function()
      session.launch('debugpy', {})
      assert.has_no.errors(function()
        session.continue()
        session.step_over()
        session.step_into()
        session.step_out()
      end)
      assert.are.same({ 'initialize' }, { last_client.requests[1].command })
    end)
  end)

  describe('evaluate', function()
    it('sends an evaluate request with the current frame id and repl context', function()
      session.launch('debugpy', {})
      session.current_frame_id = 42
      local got
      session.evaluate('1 + 1', function(resp)
        got = resp
      end)
      local req = find_request(last_client, 'evaluate')
      assert.is_not_nil(req)
      assert.are.equal('1 + 1', req.args.expression)
      assert.are.equal(42, req.args.frameId)
      assert.are.equal('repl', req.args.context)

      req.callback({ success = true, body = { result = '2' } })
      assert.is_true(got.success)
      assert.are.equal('2', got.body.result)
    end)

    it('calls back with a synthetic failure when there is no active session', function()
      local got
      session.evaluate('1 + 1', function(resp)
        got = resp
      end)
      assert.is_false(got.success)
    end)
  end)

  describe('terminate', function()
    it('sends disconnect and closes the client', function()
      session.launch('debugpy', {})
      local client = last_client
      session.terminate()
      assert.is_not_nil(find_request(client, 'disconnect'))
      assert.is_false(client.running)
      assert.is_nil(session.client)
      assert.are.equal('inactive', session.status)
    end)

    it('is a no-op with no active session', function()
      assert.has_no.errors(function()
        session.terminate()
      end)
    end)
  end)

  describe('on_exit', function()
    it('sets status to inactive and emits exited', function()
      session.launch('debugpy', {})
      local seen
      session.subscribe(function(kind, data)
        if kind == 'exited' then
          seen = data
        end
      end)
      last_opts.on_exit(1)
      assert.are.equal('inactive', session.status)
      assert.are.equal(1, seen)
    end)
  end)

  describe('is_active', function()
    it('is false before launch and true after', function()
      assert.is_false(session.is_active())
      session.launch('debugpy', {})
      assert.is_true(session.is_active())
    end)

    it('is false once the client stops running', function()
      session.launch('debugpy', {})
      last_client.running = false
      assert.is_false(session.is_active())
    end)
  end)
end)

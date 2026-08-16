-- mep.ai.job.request is mocked directly (save/replace/restore, per
-- spec/README.md) so no real curl subprocess or job.lua logic is
-- exercised here -- this file is purely about the orchestration loop:
-- turn-taking, permission gating, and transcript bookkeeping.
-- mep.ai.panel is mocked the same way, standing in for a real mep.
-- sidebar window this file has no interest in driving -- panel_spec.lua
-- already covers the real UI. mep.ai.tools.registry's run_command/
-- read_file entries are swapped for fakes too, so no real filesystem/
-- shell access happens either.
local agent = require('mep.ai.agent')
local job_mod = require('mep.ai.job')
local panel = require('mep.ai.panel')
local tools_mod = require('mep.ai.tools')
local config = require('mep.ai.config')

describe('mep.ai.agent', function()
  local orig_request, orig_panel_open, orig_panel_render, orig_panel_close
  local orig_read_file_run, orig_run_command_run
  local orig_config_options
  local requests -- { {provider, messages, tools}, ... }, one per job_mod.request call

  before_each(function()
    orig_config_options = vim.deepcopy(config.options)
    config.setup({ provider = 'openai', providers = { openai = { api_key = 'sk-test' } } })

    requests = {}
    orig_request = job_mod.request
    job_mod.request = function(provider, messages, tools, on_done)
      requests[#requests + 1] = { provider = provider, messages = vim.deepcopy(messages), tools = tools }
      local handle = { killed = false }
      handle.kill = function()
        handle.killed = true
      end
      -- Deferred, not called synchronously: mirrors the real async
      -- contract (M.start returns before on_done ever fires) and lets a
      -- test call handle.kill() before responding, same as job_spec's
      -- own "kill() suppresses..." tests exercise for mep.ai.job itself.
      handle._respond = function(err, parsed)
        if not handle.killed then
          on_done(err, parsed)
        end
      end
      requests[#requests].handle = handle
      return handle
    end

    orig_panel_open = panel.open
    orig_panel_render = panel.render
    orig_panel_close = panel.close
    panel.open = function() end
    panel.render = function() end
    panel.close = function() end

    orig_read_file_run = tools_mod.registry.read_file.run
    orig_run_command_run = tools_mod.registry.run_command.run
  end)

  after_each(function()
    job_mod.request = orig_request
    panel.open = orig_panel_open
    panel.render = orig_panel_render
    panel.close = orig_panel_close
    tools_mod.registry.read_file.run = orig_read_file_run
    tools_mod.registry.run_command.run = orig_run_command_run
    config.options = orig_config_options
    agent._reset()
  end)

  -- The last-queued job's own `_respond` -- every test in this file only
  -- ever has one request in flight at a time (a turn always waits for
  -- the previous one to settle before the next is sent).
  local function respond(err, parsed)
    requests[#requests].handle._respond(err, parsed)
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  describe('M.start', function()
    it('sends the whole buffer as context in the first request, with no scope given', function()
      local bufnr = make_buf({ 'line one', 'line two' })
      agent.start({ bufnr = bufnr })
      assert.are.equal(1, #requests)
      local user_msg = requests[1].messages[2]
      assert.are.equal('user', user_msg.role)
      assert.matches('line one', user_msg.content)
      assert.matches('line two', user_msg.content)
      assert.is_nil(user_msg.content:match('Editable target'))
    end)

    it('includes the selected block as the editable target on top of the whole buffer, for a scoped call', function()
      local bufnr = make_buf({ 'line one', 'line two', 'line three' })
      agent.start({ bufnr = bufnr, scope = { 2, 2 } })
      local user_msg = requests[1].messages[2]
      assert.matches('Editable target %-%- lines 2%-2', user_msg.content)
      assert.matches('line two', user_msg.content)
      -- still includes the full buffer too
      assert.matches('line one', user_msg.content)
      assert.matches('line three', user_msg.content)
    end)

    it('includes opts.instructions in the initial context when given', function()
      local bufnr = make_buf({ 'x' })
      agent.start({ bufnr = bufnr, instructions = 'refactor this' })
      assert.matches('Instructions: refactor this', requests[1].messages[2].content)
    end)

    it('uses config.options.tool_agent_system_prompt as the system message', function()
      local bufnr = make_buf({ 'x' })
      agent.start({ bufnr = bufnr })
      assert.are.same({ role = 'system', content = config.options.tool_agent_system_prompt }, requests[1].messages[1])
    end)

    it('offers exactly the tools listed in config.options.tools', function()
      config.setup({ tools = { 'read_file' } })
      local bufnr = make_buf({ 'x' })
      agent.start({ bufnr = bufnr })
      assert.are.equal(1, #requests[1].tools)
      assert.are.equal('read_file', requests[1].tools[1].name)
    end)

    it('records a user-role transcript entry describing the call', function()
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr, instructions = 'do the thing' })
      assert.are.equal('user', session.transcript[1].role)
      assert.are.equal('do the thing', session.transcript[1].text)
    end)
  end)

  describe('a plain text turn (no tool calls)', function()
    it('records the assistant reply and returns to idle', function()
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, { text = 'all done here', tool_calls = {} })
      assert.is_false(session.busy)
      assert.is_nil(session.job)
      local last = session.transcript[#session.transcript]
      assert.are.equal('assistant', last.role)
      assert.are.equal('all done here', last.text)
    end)

    it('records an error entry and returns to idle on failure', function()
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond('connection refused', nil)
      assert.is_false(session.busy)
      local last = session.transcript[#session.transcript]
      assert.are.equal('error', last.role)
      assert.matches('connection refused', last.text)
    end)
  end)

  describe('tool-calling turns', function()
    it('runs a read-risk tool immediately once permission is granted, then continues the conversation', function()
      tools_mod.registry.read_file.run = function(args, callback)
        callback(true, 'file contents: ' .. args.path)
      end
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, {
        text = '',
        tool_calls = { { id = 'c1', name = 'read_file', arguments = { path = 'foo.txt' }, raw_arguments = '{"path":"foo.txt"}' } },
      })

      assert.is_not_nil(session.pending)
      assert.are.equal('read_file', session.pending.tool_name)
      assert.is_true(session.pending.allow_always)
      session.pending.on_decide('allow')

      assert.is_nil(session.pending)
      -- the tool ran, its result got appended, and the conversation continued with a second request
      assert.are.equal(2, #requests)
      local last_tool_result = requests[2].messages[#requests[2].messages]
      assert.matches('file contents: foo.txt', last_tool_result.content)

      respond(nil, { text = 'read it, all good', tool_calls = {} })
      assert.are.equal('read it, all good', session.transcript[#session.transcript].text)
    end)

    it('never offers "always allow" for run_command, even after a read tool has one granted', function()
      local ran = false
      tools_mod.registry.run_command.run = function(_, callback)
        ran = true
        callback(true, 'ok')
      end
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, {
        text = '',
        tool_calls = { { id = 'c1', name = 'run_command', arguments = { command = 'ls' }, raw_arguments = '{"command":"ls"}' } },
      })

      assert.is_not_nil(session.pending)
      assert.is_false(session.pending.allow_always)
      assert.matches('Run: ls', session.pending.description)
      session.pending.on_decide('allow')
      assert.is_true(ran)

      -- a second run_command call in a later turn asks again -- "allow"
      -- (not "always") never grants a standing permission
      respond(nil, {
        text = '',
        tool_calls = { { id = 'c2', name = 'run_command', arguments = { command = 'pwd' }, raw_arguments = '{"command":"pwd"}' } },
      })
      assert.is_not_nil(session.pending)
      assert.are.equal('run_command', session.pending.tool_name)
    end)

    it('an "always" decision on a read tool skips the prompt for later calls to that same tool', function()
      local call_count = 0
      tools_mod.registry.read_file.run = function(_, callback)
        call_count = call_count + 1
        callback(true, 'ok')
      end
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, {
        text = '',
        tool_calls = { { id = 'c1', name = 'read_file', arguments = { path = 'a' }, raw_arguments = '{}' } },
      })
      session.pending.on_decide('always')
      assert.are.equal(1, call_count)

      respond(nil, {
        text = '',
        tool_calls = { { id = 'c2', name = 'read_file', arguments = { path = 'b' }, raw_arguments = '{}' } },
      })
      -- no permission prompt this time -- ran straight away
      assert.is_nil(session.pending)
      assert.are.equal(2, call_count)
    end)

    it('a "deny" decision records the denial as an error-tagged tool result and continues without running the tool', function()
      local ran = false
      tools_mod.registry.run_command.run = function(_, callback)
        ran = true
        callback(true, 'ok')
      end
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, {
        text = '',
        tool_calls = { { id = 'c1', name = 'run_command', arguments = { command = 'rm -rf /' }, raw_arguments = '{}' } },
      })
      session.pending.on_decide('deny')

      assert.is_false(ran)
      assert.is_nil(session.pending)
      assert.are.equal(2, #requests)
      local tool_result = requests[2].messages[#requests[2].messages]
      assert.matches('^Error: denied by user$', tool_result.content)
    end)

    it('runs multiple tool calls in one turn in sequence, gating each independently', function()
      local order = {}
      tools_mod.registry.read_file.run = function(args, callback)
        order[#order + 1] = 'ran:' .. args.path
        callback(true, 'contents of ' .. args.path)
      end
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, {
        text = '',
        tool_calls = {
          { id = 'c1', name = 'read_file', arguments = { path = 'a' }, raw_arguments = '{}' },
          { id = 'c2', name = 'read_file', arguments = { path = 'b' }, raw_arguments = '{}' },
        },
      })
      assert.is_not_nil(session.pending)
      session.pending.on_decide('allow')
      assert.is_not_nil(session.pending) -- second call now pending
      session.pending.on_decide('allow')

      assert.are.same({ 'ran:a', 'ran:b' }, order)
      assert.are.equal(2, #requests)
    end)
  end)

  describe('M.cancel / on_reply', function()
    it('cancel() kills the in-flight job and marks the session idle again', function()
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      assert.is_true(session.busy)
      agent.cancel()
      assert.is_false(session.busy)
      assert.is_nil(session.job)
      assert.are.equal('info', session.transcript[#session.transcript].role)
    end)

    it('is_busy() reflects whether a request is currently in flight', function()
      local bufnr = make_buf({ 'x' })
      agent.start({ bufnr = bufnr })
      assert.is_true(agent.is_busy())
      respond(nil, { text = 'done', tool_calls = {} })
      assert.is_false(agent.is_busy())
    end)

    it('on_reply appends a user message and starts a new turn', function()
      local bufnr = make_buf({ 'x' })
      local session = agent.start({ bufnr = bufnr })
      respond(nil, { text = 'first answer', tool_calls = {} })
      session.on_reply('and another thing')
      assert.are.equal(2, #requests)
      local msgs = requests[2].messages
      assert.are.equal('and another thing', msgs[#msgs].content)
      respond(nil, { text = 'second answer', tool_calls = {} })
      assert.are.equal('second answer', session.transcript[#session.transcript].text)
    end)
  end)

  it('starting a new session cancels the previous one\'s in-flight request', function()
    local bufnr = make_buf({ 'x' })
    agent.start({ bufnr = bufnr })
    local first_handle = requests[1].handle
    agent.start({ bufnr = bufnr })
    assert.is_true(first_handle.killed)
  end)
end)

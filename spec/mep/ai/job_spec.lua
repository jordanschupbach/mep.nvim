-- Mocks vim.fn.jobstart (the same core.job.spawn contract every other
-- job-backed spec in this suite mocks — see spec/README.md) rather than
-- spawning a real curl process. Body files are real temp files (writefile/
-- delete run for real, same as mep.org.babel's own specs).
local job = require('mep.ai.job')

describe('mep.ai.job', function()
  local orig_jobstart, orig_jobstop
  local captured

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    orig_jobstop = vim.fn.jobstop
    captured = nil
    vim.fn.jobstart = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      return 1
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobstop = orig_jobstop
  end)

  local provider = { kind = 'openai', model = 'x', endpoint = 'http://localhost:11434/v1/chat/completions' }
  local messages = { { role = 'user', content = 'hi' } }

  it('builds a "curl -N --fail-with-body -X POST <endpoint>" command with the JSON content-type header', function()
    job.start(provider, messages, function() end, function() end)
    assert.are.same(
      { 'curl', '-s', '-N', '--fail-with-body', '-X', 'POST', provider.endpoint, '-H', 'Content-Type: application/json' },
      { table.unpack(captured.cmd, 1, 9) }
    )
  end)

  it('adds an Authorization header for a provider with an api_key', function()
    job.start({ kind = 'openai', model = 'x', endpoint = 'http://x', api_key = 'sk-1' }, messages, function() end, function() end)
    local found = false
    for i, arg in ipairs(captured.cmd) do
      if arg == '-H' and captured.cmd[i + 1] == 'Authorization: Bearer sk-1' then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it('writes the request body to a real temp file passed as --data-binary @<path>', function()
    job.start(provider, messages, function() end, function() end)
    local idx
    for i, arg in ipairs(captured.cmd) do
      if arg == '--data-binary' then
        idx = i
      end
    end
    local body_path = captured.cmd[idx + 1]:sub(2) -- strip leading '@'
    local body = vim.json.decode(vim.fn.readfile(body_path)[1])
    assert.are.same({ model = 'x', messages = messages, stream = true }, body)
    vim.fn.delete(body_path)
  end)

  it('streams SSE "data:" lines through the provider delta extractor', function()
    local deltas = {}
    job.start(provider, messages, function(text)
      deltas[#deltas + 1] = text
    end, function() end)

    captured.opts.on_stdout(1, { 'data: {"choices":[{"delta":{"content":"Hel"}}]}', '' })
    captured.opts.on_stdout(1, { 'data: {"choices":[{"delta":{"content":"lo"}}]}', '' })
    captured.opts.on_stdout(1, { 'data: [DONE]', '' })
    captured.opts.on_exit(1, 0)

    assert.are.same({ 'Hel', 'lo' }, deltas)
  end)

  it('ignores blank lines and non-"data:" lines in the stream', function()
    local deltas = {}
    job.start(provider, messages, function(text)
      deltas[#deltas + 1] = text
    end, function() end)

    captured.opts.on_stdout(1, { '', 'event: message', 'data: {"choices":[{"delta":{"content":"x"}}]}', '' })
    captured.opts.on_exit(1, 0)

    assert.are.same({ 'x' }, deltas)
  end)

  it('calls on_done(nil) on a successful stream that produced at least one delta', function()
    local done_err = 'not called'
    job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    captured.opts.on_stdout(1, { 'data: {"choices":[{"delta":{"content":"x"}}]}', '' })
    captured.opts.on_exit(1, 0)
    assert.is_nil(done_err)
  end)

  it('calls on_done with a "no response received" error when exit 0 but nothing streamed', function()
    local done_err
    job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    captured.opts.on_exit(1, 0)
    assert.matches('^no response received', done_err)
  end)

  it('surfaces a JSON error body ({"error":{"message":...}}) on a nonzero exit', function()
    local done_err
    job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    captured.opts.on_stdout(1, { '{"error":{"message":"invalid api key"}}', '' })
    captured.opts.on_exit(1, 22)
    assert.matches('exit 22', done_err)
    assert.matches('invalid api key', done_err)
  end)

  it('prefers curl-level stderr over the response body when both are present', function()
    local done_err
    job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    captured.opts.on_stderr(1, { 'curl: (7) Failed to connect', '' })
    captured.opts.on_exit(1, 7)
    assert.matches('Failed to connect', done_err)
  end)

  it('falls back to the raw body verbatim when it does not parse as JSON', function()
    local done_err
    job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    captured.opts.on_stdout(1, { '<html>502 Bad Gateway</html>', '' })
    captured.opts.on_exit(1, 1)
    assert.matches('502 Bad Gateway', done_err)
  end)

  it('kill() stops the underlying job', function()
    local stopped_id
    vim.fn.jobstop = function(id)
      stopped_id = id
    end
    local handle = job.start(provider, messages, function() end, function() end)
    handle.kill()
    assert.are.equal(1, stopped_id)
  end)

  it('kill() suppresses the "request failed" error a SIGTERM exit would otherwise produce', function()
    local done_err = 'not called'
    local handle = job.start(provider, messages, function() end, function(err)
      done_err = err
    end)
    -- a partial SSE chunk mid-flight when the process gets killed, same
    -- as a real curl subprocess would leave behind
    captured.opts.on_stdout(1, { 'data: {"choices":[{"delta":{"content":"partial"}}]}', '' })
    handle.kill()
    -- the real subprocess terminating (SIGTERM, exit 143) after kill()
    captured.opts.on_exit(1, 143)
    assert.is_nil(done_err)
  end)

  describe('request (non-streaming, tool-calling)', function()
    it('builds a "curl --fail-with-body -X POST <endpoint>" command with no -N flag', function()
      job.request(provider, messages, nil, function() end)
      assert.are.same(
        { 'curl', '-s', '--fail-with-body', '-X', 'POST', provider.endpoint, '-H', 'Content-Type: application/json' },
        { table.unpack(captured.cmd, 1, 8) }
      )
    end)

    it('sends stream = false and the given tools in the request body', function()
      local tools = { { name = 'read_file', description = 'x', parameters = {} } }
      job.request(provider, messages, tools, function() end)
      local idx
      for i, arg in ipairs(captured.cmd) do
        if arg == '--data-binary' then
          idx = i
        end
      end
      local body_path = captured.cmd[idx + 1]:sub(2)
      local body = vim.json.decode(vim.fn.readfile(body_path)[1])
      assert.is_false(body.stream)
      assert.are.equal('read_file', body.tools[1]['function'].name)
      vim.fn.delete(body_path)
    end)

    it('calls on_done(nil, parsed) with the parsed response on success', function()
      local err, parsed
      job.request(provider, messages, nil, function(e, p)
        err, parsed = e, p
      end)
      captured.opts.on_stdout(1, { '{"choices":[{"message":{"content":"hi there"}}]}', '' })
      captured.opts.on_exit(1, 0)
      assert.is_nil(err)
      assert.are.equal('hi there', parsed.text)
      assert.are.same({}, parsed.tool_calls)
    end)

    it('calls on_done(nil, parsed) with tool_calls when the model asks for one', function()
      local err, parsed
      job.request(provider, messages, nil, function(e, p)
        err, parsed = e, p
      end)
      captured.opts.on_stdout(1, {
        '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c1","function":{"name":"read_file","arguments":"{\\"path\\":\\"x\\"}"}}]}}]}',
        '',
      })
      captured.opts.on_exit(1, 0)
      assert.is_nil(err)
      assert.are.equal(1, #parsed.tool_calls)
      assert.are.equal('read_file', parsed.tool_calls[1].name)
    end)

    it('calls on_done(err, nil) on a nonzero exit, surfacing the response body', function()
      local err, parsed = 'not called', 'not called'
      job.request(provider, messages, nil, function(e, p)
        err, parsed = e, p
      end)
      captured.opts.on_stdout(1, { '{"error":{"message":"invalid api key"}}', '' })
      captured.opts.on_exit(1, 22)
      assert.matches('invalid api key', err)
      assert.is_nil(parsed)
    end)

    it('calls on_done(err, nil) when the body does not parse as JSON at all', function()
      local err, parsed = 'not called', 'not called'
      job.request(provider, messages, nil, function(e, p)
        err, parsed = e, p
      end)
      captured.opts.on_stdout(1, { 'not json', '' })
      captured.opts.on_exit(1, 0)
      assert.matches('could not parse response', err)
      assert.is_nil(parsed)
    end)

    it('kill() suppresses the error a SIGTERM exit would otherwise produce', function()
      local err, parsed = 'not called', 'not called'
      local handle = job.request(provider, messages, nil, function(e, p)
        err, parsed = e, p
      end)
      handle.kill()
      captured.opts.on_exit(1, 143)
      assert.is_nil(err)
      assert.is_nil(parsed)
    end)

    it('deletes the temp body file after the request finishes', function()
      job.request(provider, messages, nil, function() end)
      local idx
      for i, arg in ipairs(captured.cmd) do
        if arg == '--data-binary' then
          idx = i
        end
      end
      local body_path = captured.cmd[idx + 1]:sub(2)
      assert.are.equal(1, vim.fn.filereadable(body_path))
      captured.opts.on_stdout(1, { '{"choices":[{"message":{"content":"x"}}]}', '' })
      captured.opts.on_exit(1, 0)
      assert.are.equal(0, vim.fn.filereadable(body_path))
    end)
  end)
end)

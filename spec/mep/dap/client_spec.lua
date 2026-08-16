-- mep.dap.client wraps vim.fn.jobstart/vim.fn.chansend directly (not
-- mep.core.job — see the module's own header comment on why), so its
-- interesting logic (message framing/dispatch across chunk boundaries,
-- pending-request bookkeeping, exit handling) can be tested by mocking
-- those two primitives and driving jobstart's callbacks by hand, the
-- same "mock the primitive, drive it by hand" approach spec/README.md
-- documents for vim.fn.jobstart.
local Client = require('mep.dap.client')
local protocol = require('mep.dap.protocol')

describe('mep.dap.client', function()
  local orig_jobstart, orig_chansend
  local captured, sent

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    orig_chansend = vim.fn.chansend
    sent = {}
    vim.fn.jobstart = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      return 7
    end
    vim.fn.chansend = function(id, data)
      sent[#sent + 1] = { id = id, data = data }
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.chansend = orig_chansend
  end)

  it('spawns opts.cmd via jobstart', function()
    Client.new({ cmd = { 'debugpy-adapter' } })
    assert.are.same({ 'debugpy-adapter' }, captured.cmd)
  end)

  it('is_running is true once jobstart returns a positive id', function()
    local client = Client.new({ cmd = { 'x' } })
    assert.is_true(client:is_running())
  end)

  it('is_running is false when jobstart fails to start (returns <= 0)', function()
    vim.fn.jobstart = function()
      return 0
    end
    local client = Client.new({ cmd = { 'x' } })
    assert.is_false(client:is_running())
  end)

  it('sends a framed request with an incrementing seq via chansend', function()
    local client = Client.new({ cmd = { 'x' } })
    client:request('initialize', { clientID = 'mep.nvim' })
    client:request('launch', { program = '/tmp/foo.py' })

    assert.are.equal(2, #sent)
    local messages1 = protocol.parse_messages(sent[1].data)
    local messages2 = protocol.parse_messages(sent[2].data)
    assert.are.equal(1, messages1[1].seq)
    assert.are.equal('initialize', messages1[1].command)
    assert.are.equal(2, messages2[1].seq)
    assert.are.equal('launch', messages2[1].command)
    assert.are.equal(7, sent[1].id)
  end)

  it('dispatches a response to the callback matching its request_seq', function()
    local client = Client.new({ cmd = { 'x' } })
    local got
    client:request('initialize', {}, function(resp)
      got = resp
    end)

    local response = protocol.encode({ seq = 99, type = 'response', request_seq = 1, success = true, body = { ok = true } })
    captured.opts.on_stdout(1, vim.split(response, '\n', { plain = true }))

    assert.is_not_nil(got)
    assert.is_true(got.success)
    assert.are.same({ ok = true }, got.body)
  end)

  it('reassembles a message split mid-stream across two on_stdout chunks', function()
    -- Splitting the *raw byte stream* (not some already-split line list)
    -- in half and re-splitting each half on '\n' independently mirrors
    -- what jobstart itself actually hands on_stdout across two chunk
    -- deliveries — `vim.split(x, '\n')` then `table.concat(_, '\n')`
    -- round-trips any string exactly, split point included, which is
    -- the property mep.dap.client's own `_feed` buffering relies on.
    local client = Client.new({ cmd = { 'x' } })
    local got
    client:request('initialize', {}, function(resp)
      got = resp
    end)

    local response = protocol.encode({ seq = 1, type = 'response', request_seq = 1, success = true })
    local midpoint = math.floor(#response / 2)
    local first_batch = vim.split(response:sub(1, midpoint), '\n', { plain = true })
    local second_batch = vim.split(response:sub(midpoint + 1), '\n', { plain = true })

    captured.opts.on_stdout(1, first_batch)
    assert.is_nil(got)
    captured.opts.on_stdout(1, second_batch)
    assert.is_not_nil(got)
    assert.is_true(got.success)
  end)

  it('dispatches an event to on_event', function()
    local events = {}
    Client.new({
      cmd = { 'x' },
      on_event = function(event, body)
        events[#events + 1] = { event = event, body = body }
      end,
    })
    local msg = protocol.encode({ seq = 1, type = 'event', event = 'stopped', body = { threadId = 1 } })
    captured.opts.on_stdout(1, vim.split(msg, '\n', { plain = true }))

    assert.are.equal(1, #events)
    assert.are.equal('stopped', events[1].event)
    assert.are.equal(1, events[1].body.threadId)
  end)

  it('calls callback with a synthetic failure when the adapter is not running', function()
    vim.fn.jobstart = function()
      return -1
    end
    local client = Client.new({ cmd = { 'x' } })
    local got
    client:request('initialize', {}, function(resp)
      got = resp
    end)
    assert.is_false(got.success)
    assert.are.equal(0, #sent)
  end)

  it('flushes every pending request with a synthetic failure on exit', function()
    local client = Client.new({ cmd = { 'x' } })
    local got1, got2
    client:request('a', {}, function(r)
      got1 = r
    end)
    client:request('b', {}, function(r)
      got2 = r
    end)

    captured.opts.on_exit(1, 1)

    assert.is_false(got1.success)
    assert.is_false(got2.success)
    assert.is_false(client:is_running())
  end)

  it('calls on_exit with the exit code', function()
    local code_seen
    Client.new({
      cmd = { 'x' },
      on_exit = function(code)
        code_seen = code
      end,
    })
    captured.opts.on_exit(1, 3)
    assert.are.equal(3, code_seen)
  end)

  it('close() jobstops a running adapter', function()
    local orig_jobstop = vim.fn.jobstop
    local stopped_id
    vim.fn.jobstop = function(id)
      stopped_id = id
    end
    local client = Client.new({ cmd = { 'x' } })
    client:close()
    assert.are.equal(7, stopped_id)
    vim.fn.jobstop = orig_jobstop
  end)

  it('close() on an already-stopped client is a no-op', function()
    vim.fn.jobstart = function()
      return -1
    end
    local client = Client.new({ cmd = { 'x' } })
    assert.has_no.errors(function()
      client:close()
    end)
  end)
end)

-- core.job wraps vim.fn.jobstart, which means the interesting logic (line
-- buffering across chunk boundaries, exit handling) can be tested by
-- mocking vim.fn.jobstart itself and driving its callbacks by hand — no
-- real subprocess involved, so none of nlua's subprocess-cleanup quirks
-- (see spec/README.md) come into play here.
local job = require('mep.core.job')

describe('mep.core.job', function()
  local orig_jobstart
  local captured

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    captured = nil
    vim.fn.jobstart = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      return 42
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
  end)

  it('passes cmd, cwd, and env through to jobstart', function()
    job.spawn({ cmd = { 'rg', '--files' }, cwd = '/tmp', env = { FOO = 'bar' } })
    assert.are.same({ 'rg', '--files' }, captured.cmd)
    assert.are.equal('/tmp', captured.opts.cwd)
    assert.are.same({ FOO = 'bar' }, captured.opts.env)
  end)

  it('joins a line split across multiple on_stdout chunks', function()
    local lines = {}
    job.spawn({
      cmd = { 'x' },
      on_stdout = function(l)
        table.insert(lines, l)
      end,
    })

    -- "hello\nworld" arriving as two raw reads: "hel" then "lo\nworld"
    captured.opts.on_stdout(1, { 'hel' })
    captured.opts.on_stdout(1, { 'lo', 'world' })
    assert.are.same({ 'hello' }, lines)

    -- 'world' has no trailing newline yet, so it's flushed on exit
    captured.opts.on_exit(1, 0)
    assert.are.same({ 'hello', 'world' }, lines)
  end)

  it('does not emit a spurious empty line when a chunk ends exactly on a newline', function()
    local lines = {}
    job.spawn({
      cmd = { 'x' },
      on_stdout = function(l)
        table.insert(lines, l)
      end,
    })

    captured.opts.on_stdout(1, { 'a', 'b', '' })
    assert.are.same({ 'a', 'b' }, lines)

    captured.opts.on_exit(1, 0)
    assert.are.same({ 'a', 'b' }, lines) -- exit flush is a no-op: pending is empty
  end)

  it('keeps stdout and stderr lines separate', function()
    local out, err = {}, {}
    job.spawn({
      cmd = { 'x' },
      on_stdout = function(l)
        table.insert(out, l)
      end,
      on_stderr = function(l)
        table.insert(err, l)
      end,
    })

    captured.opts.on_stdout(1, { 'out1', '' })
    captured.opts.on_stderr(1, { 'err1', '' })

    assert.are.same({ 'out1' }, out)
    assert.are.same({ 'err1' }, err)
  end)

  it('calls on_exit with the process exit code', function()
    local code
    job.spawn({
      cmd = { 'x' },
      on_exit = function(c)
        code = c
      end,
    })
    captured.opts.on_exit(1, 7)
    assert.are.equal(7, code)
  end)

  it('kill() calls jobstop with this job\'s id', function()
    local orig_jobstop = vim.fn.jobstop
    local stopped_id
    vim.fn.jobstop = function(id)
      stopped_id = id
    end

    local handle = job.spawn({ cmd = { 'x' } })
    handle.kill()

    assert.are.equal(42, stopped_id)
    vim.fn.jobstop = orig_jobstop
  end)

  it('schedules on_exit(-1) when jobstart fails to start', function()
    vim.fn.jobstart = function()
      return -1
    end

    local code
    job.spawn({
      cmd = { 'nonexistent' },
      on_exit = function(c)
        code = c
      end,
    })

    vim.wait(200, function()
      return code ~= nil
    end, 5)
    assert.are.equal(-1, code)
  end)

  it('requires cmd to be a table', function()
    assert.has_error(function()
      job.spawn({ cmd = 'not-a-table' })
    end)
  end)
end)

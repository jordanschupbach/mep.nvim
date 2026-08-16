-- mep.leetcode.runner drives mep.org.babel.execute for real, which
-- itself spawns vim.fn.jobstart — mocked here the exact same way
-- spec/mep/org/babel_spec.lua mocks it for its own "execute" tests, so
-- no real subprocess ever runs (see spec/README.md).
local runner = require('mep.leetcode.runner')

describe('mep.leetcode.runner', function()
  local orig_jobstart, orig_executable
  local captured_cmd, captured_opts

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    orig_executable = vim.fn.executable
    vim.fn.executable = function(name)
      return name == 'python3' and 1 or 0
    end
    vim.fn.jobstart = function(cmd, opts)
      captured_cmd = cmd
      captured_opts = opts
      return 42
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.executable = orig_executable
  end)

  describe('run_one', function()
    it('splices the solution body above the test body into one script', function()
      local solution = { body = { 'def add(a, b):', '    return a + b' } }
      local test = { body = { 'print(add(1, 2))' } }

      runner.run_one('python', solution, test, function() end)

      assert.are.equal('python3', captured_cmd[1])
      assert.are.same({ 'def add(a, b):', '    return a + b', 'print(add(1, 2))' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('calls on_done with stdout/stderr/exit code from the spawned job', function()
      local solution = { body = { 'x = 1' } }
      local test = { body = { 'print(x)' } }
      local got_code, got_stdout, got_stderr

      runner.run_one('python', solution, test, function(code, stdout, stderr)
        got_code, got_stdout, got_stderr = code, stdout, stderr
      end)

      captured_opts.on_stdout(42, { '1', '' })
      captured_opts.on_exit(42, 0)

      assert.are.equal(0, got_code)
      assert.are.same({ '1' }, got_stdout)
      assert.are.same({}, got_stderr)
    end)

    it('deletes the scratch buffer after on_done', function()
      local solution = { body = { 'x = 1' } }
      local test = { body = { 'print(x)' } }
      local buf_count_before = #vim.api.nvim_list_bufs()

      runner.run_one('python', solution, test, function() end)
      captured_opts.on_exit(42, 0)

      vim.wait(100, function()
        return #vim.api.nvim_list_bufs() <= buf_count_before
      end, 5)
      assert.is_true(#vim.api.nvim_list_bufs() <= buf_count_before)
    end)
  end)

  describe('run_all', function()
    it('runs every test sequentially, calling on_each per test and on_all_done at the end', function()
      local solution = { body = { 'x = 1' } }
      local tests = { { body = { 'print(1)' } }, { body = { 'print(2)' } } }
      local results = {}
      local finished = false

      runner.run_all('python', solution, tests, function(i, code, stdout, stderr)
        results[#results + 1] = { i = i, code = code, stdout = stdout, stderr = stderr }
      end, function()
        finished = true
      end)

      -- First test's job has been spawned but not yet exited.
      assert.are.equal(0, #results)
      captured_opts.on_exit(42, 0)
      assert.are.equal(1, #results)
      assert.are.equal(1, results[1].i)

      -- Second test's job only starts once the first finished.
      assert.is_false(finished)
      captured_opts.on_exit(42, 0)
      assert.are.equal(2, #results)
      assert.are.equal(2, results[2].i)
      assert.is_true(finished)
    end)

    it('calls on_all_done immediately for an empty test list', function()
      local finished = false
      runner.run_all('python', { body = {} }, {}, function() end, function()
        finished = true
      end)
      assert.is_true(finished)
    end)
  end)
end)

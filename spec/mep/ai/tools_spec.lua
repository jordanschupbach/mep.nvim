-- read_file/list_dir hit the real filesystem (temp files/dirs, same
-- convention mep.org.babel's own specs use); run_command mocks
-- vim.fn.jobstart the way every other job-backed spec in this suite
-- does (see spec/README.md) rather than spawning a real subprocess.
local tools = require('mep.ai.tools')

describe('mep.ai.tools', function()
  describe('read_file', function()
    it('calls back with the file contents on success', function()
      local path = vim.fn.tempname()
      vim.fn.writefile({ 'line one', 'line two' }, path)
      local ok, result
      tools.registry.read_file.run({ path = path }, function(o, r)
        ok, result = o, r
      end)
      assert.is_true(ok)
      assert.are.equal('line one\nline two', result)
      vim.fn.delete(path)
    end)

    it('calls back with ok=false for a nonexistent file', function()
      local ok, result
      tools.registry.read_file.run({ path = '/does/not/exist/at/all' }, function(o, r)
        ok, result = o, r
      end)
      assert.is_false(ok)
      assert.matches('not a readable file', result)
    end)

    it('is marked risk = read', function()
      assert.are.equal('read', tools.registry.read_file.risk)
    end)
  end)

  describe('list_dir', function()
    local dir

    before_each(function()
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
    end)
    after_each(function()
      vim.fn.delete(dir, 'rf')
    end)

    it('lists entries, sorted', function()
      vim.fn.writefile({}, dir .. '/b.txt')
      vim.fn.writefile({}, dir .. '/a.txt')
      local ok, result
      tools.registry.list_dir.run({ path = dir }, function(o, r)
        ok, result = o, r
      end)
      assert.is_true(ok)
      assert.are.equal('a.txt\nb.txt', result)
    end)

    it('reports an empty directory distinctly', function()
      local ok, result
      tools.registry.list_dir.run({ path = dir }, function(o, r)
        ok, result = o, r
      end)
      assert.is_true(ok)
      assert.are.equal('(empty directory)', result)
    end)

    it('defaults to the current working directory when path is omitted', function()
      local ok
      tools.registry.list_dir.run({}, function(o)
        ok = o
      end)
      assert.is_true(ok)
    end)

    it('calls back with ok=false for a non-directory path', function()
      local file = dir .. '/f.txt'
      vim.fn.writefile({}, file)
      local ok, result
      tools.registry.list_dir.run({ path = file }, function(o, r)
        ok, result = o, r
      end)
      assert.is_false(ok)
      assert.matches('not a directory', result)
    end)

    it('is marked risk = read', function()
      assert.are.equal('read', tools.registry.list_dir.risk)
    end)
  end)

  describe('run_command', function()
    local orig_jobstart
    local captured

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      captured = nil
      vim.fn.jobstart = function(cmd, opts)
        captured = { cmd = cmd, opts = opts }
        return 1
      end
    end)
    after_each(function()
      vim.fn.jobstart = orig_jobstart
    end)

    it('runs the command via sh -c', function()
      tools.registry.run_command.run({ command = 'echo hi' }, function() end)
      assert.are.same({ 'sh', '-c', 'echo hi' }, captured.cmd)
    end)

    it('calls back with ok=true and formatted stdout on a zero exit', function()
      local ok, result
      tools.registry.run_command.run({ command = 'echo hi' }, function(o, r)
        ok, result = o, r
      end)
      captured.opts.on_stdout(1, { 'hi', '' })
      captured.opts.on_exit(1, 0)
      assert.is_true(ok)
      assert.matches('exit code: 0', result)
      assert.matches('stdout:\nhi', result)
    end)

    it('calls back with ok=false and includes stderr on a nonzero exit', function()
      local ok, result
      tools.registry.run_command.run({ command = 'false' }, function(o, r)
        ok, result = o, r
      end)
      captured.opts.on_stderr(1, { 'boom', '' })
      captured.opts.on_exit(1, 1)
      assert.is_false(ok)
      assert.matches('exit code: 1', result)
      assert.matches('stderr:\nboom', result)
    end)

    it('is marked risk = exec, unlike the read-only tools', function()
      assert.are.equal('exec', tools.registry.run_command.risk)
    end)
  end)

  describe('names', function()
    it('returns exactly the registry keys, sorted', function()
      assert.are.same({ 'list_dir', 'read_file', 'run_command' }, tools.names())
    end)
  end)
end)

-- All git access goes through mep.core.job -> vim.fn.jobstart; mocked
-- here rather than run for real (see spec/README.md: no real
-- subprocess inside the busted/nlua harness).
local status = require('mep.git.status')

describe('mep.git.status', function()
  local orig_jobstart
  local captured

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    captured = nil
    vim.fn.jobstart = function(cmd, jopts)
      captured = { cmd = cmd, opts = jopts }
      return 42
    end
    status._reset()
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    status._reset()
  end)

  describe('refresh', function()
    it('runs `git status --porcelain=v1` in root', function()
      status.refresh('/repo', function() end)
      assert.are.same({ 'git', 'status', '--porcelain=v1' }, captured.cmd)
      assert.are.equal('/repo', captured.opts.cwd)
    end)

    it('splits staged, unstaged, and untracked entries', function()
      local result
      status.refresh('/repo', function(st)
        result = st
      end)
      captured.opts.on_stdout(1, {
        'M  staged_only.lua', -- staged modify
        ' M unstaged_only.lua', -- unstaged modify
        'MM both.lua', -- staged and unstaged
        '?? new_file.lua', -- untracked
        '',
      })
      captured.opts.on_exit(1, 0)

      assert.is_not_nil(result)
      assert.are.equal('/repo', result.root)

      local function paths(list)
        local out = {}
        for _, e in ipairs(list) do
          out[#out + 1] = e.path
        end
        table.sort(out)
        return out
      end

      assert.are.same({ 'both.lua', 'staged_only.lua' }, paths(result.staged))
      assert.are.same({ 'both.lua', 'unstaged_only.lua' }, paths(result.unstaged))
      assert.are.same({ 'new_file.lua' }, paths(result.untracked))
    end)

    it('keeps only the new path for a rename', function()
      local result
      status.refresh('/repo', function(st)
        result = st
      end)
      captured.opts.on_stdout(1, { 'R  old_name.lua -> new_name.lua', '' })
      captured.opts.on_exit(1, 0)
      assert.are.equal('new_name.lua', result.staged[1].path)
    end)

    it('leaves the previous cache in place on a non-zero exit', function()
      status.refresh('/repo', function() end)
      captured.opts.on_stdout(1, { 'M  first.lua', '' })
      captured.opts.on_exit(1, 0)

      status.refresh('/other', function() end)
      captured.opts.on_stdout(1, { 'M  second.lua', '' })
      captured.opts.on_exit(1, 1) -- failure

      assert.are.equal('/repo', status.get().root)
      assert.are.equal('first.lua', status.get().staged[1].path)
    end)

    it('calls back with the cache even on failure', function()
      local called = false
      status.refresh('/repo', function()
        called = true
      end)
      captured.opts.on_exit(1, 1)
      assert.is_true(called)
    end)
  end)

  describe('get', function()
    it('is empty lists before any refresh', function()
      assert.are.same({}, status.get().staged)
      assert.are.same({}, status.get().unstaged)
      assert.are.same({}, status.get().untracked)
    end)
  end)

  describe('stage / unstage / discard / commit', function()
    it('stage runs git add -- path', function()
      status.stage('/repo', 'foo.lua', function() end)
      assert.are.same({ 'git', 'add', '--', 'foo.lua' }, captured.cmd)
      assert.are.equal('/repo', captured.opts.cwd)
    end)

    it('unstage runs git reset -- path', function()
      status.unstage('/repo', 'foo.lua', function() end)
      assert.are.same({ 'git', 'reset', '--', 'foo.lua' }, captured.cmd)
    end)

    it('discard on a tracked file runs git checkout -- path', function()
      status.discard('/repo', 'foo.lua', false, function() end)
      assert.are.same({ 'git', 'checkout', '--', 'foo.lua' }, captured.cmd)
    end)

    it('discard on an untracked file deletes it from disk without spawning git', function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, 'p')
      vim.fn.writefile({ 'hi' }, tmp .. '/scratch.txt')
      local ok
      status.discard(tmp, 'scratch.txt', true, function(result)
        ok = result
      end)
      assert.is_nil(captured) -- no subprocess spawned
      assert.is_true(ok)
      assert.are.equal(0, vim.fn.filereadable(tmp .. '/scratch.txt'))
      vim.fn.delete(tmp, 'rf')
    end)

    it('commit runs git commit -m message', function()
      status.commit('/repo', 'fix the thing', function() end)
      assert.are.same({ 'git', 'commit', '-m', 'fix the thing' }, captured.cmd)
    end)

    it('callback reflects a non-zero exit as not ok', function()
      local ok = 'unset'
      status.stage('/repo', 'foo.lua', function(result)
        ok = result
      end)
      captured.opts.on_exit(1, 1)
      assert.is_false(ok)
    end)

    it('callback reflects a zero exit as ok', function()
      local ok = 'unset'
      status.unstage('/repo', 'foo.lua', function(result)
        ok = result
      end)
      captured.opts.on_exit(1, 0)
      assert.is_true(ok)
    end)
  end)
end)

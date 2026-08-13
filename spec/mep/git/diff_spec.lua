local diff = require('mep.git.diff')

describe('mep.git.diff', function()
  describe('get_indexed_content', function()
    local orig_jobstart
    local captured

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      captured = nil
      vim.fn.jobstart = function(cmd, jopts)
        captured = { cmd = cmd, opts = jopts }
        return 42
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
    end)

    it('runs `git show :relpath` in root', function()
      diff.get_indexed_content('/repo', 'lua/foo.lua', function() end)
      assert.are.same({ 'git', 'show', ':lua/foo.lua' }, captured.cmd)
      assert.are.equal('/repo', captured.opts.cwd)
    end)

    it('joins stdout lines and calls back with the content on exit 0', function()
      local result
      diff.get_indexed_content('/repo', 'foo.lua', function(content)
        result = content
      end)
      captured.opts.on_stdout(1, { 'local a = 1', 'local b = 2', '' })
      captured.opts.on_exit(1, 0)
      assert.are.equal('local a = 1\nlocal b = 2', result)
    end)

    it('calls back with nil on a non-zero exit (e.g. untracked file)', function()
      local result = 'unset'
      diff.get_indexed_content('/repo', 'foo.lua', function(content)
        result = content
      end)
      captured.opts.on_exit(1, 128)
      assert.is_nil(result)
    end)
  end)

  describe('split_lines', function()
    it('splits on newlines', function()
      assert.are.same({ 'a', 'b', 'c' }, diff.split_lines('a\nb\nc'))
    end)

    it('returns an empty list for nil or an empty string', function()
      assert.are.same({}, diff.split_lines(nil))
      assert.are.same({}, diff.split_lines(''))
    end)
  end)

  describe('compute_hunks', function()
    it('is empty for identical text', function()
      assert.are.same({}, diff.compute_hunks('a\nb\n', 'a\nb\n'))
    end)

    it('detects a single-line change', function()
      local hunks = diff.compute_hunks('a\nb\nc\n', 'a\nB\nc\n')
      assert.are.equal(1, #hunks)
      assert.are.same({ kind = 'change', start_a = 2, count_a = 1, start_b = 2, count_b = 1 }, hunks[1])
    end)

    it('detects a pure addition', function()
      local hunks = diff.compute_hunks('a\nb\n', 'a\nb\nc\nd\n')
      assert.are.equal(1, #hunks)
      assert.are.same({ kind = 'add', start_a = 2, count_a = 0, start_b = 3, count_b = 2 }, hunks[1])
    end)

    it('detects a pure deletion', function()
      local hunks = diff.compute_hunks('a\nb\nc\n', 'a\nc\n')
      assert.are.equal(1, #hunks)
      assert.are.same({ kind = 'delete', start_a = 2, count_a = 1, start_b = 1, count_b = 0 }, hunks[1])
    end)

    it('marks a deletion at the very top of the file with start_b = 0', function()
      local hunks = diff.compute_hunks('a\nb\nc\n', 'b\nc\n')
      assert.are.equal(1, #hunks)
      assert.are.same({ kind = 'delete', start_a = 1, count_a = 1, start_b = 0, count_b = 0 }, hunks[1])
    end)

    it('treats a nil/empty old text as "every line added" (untracked file)', function()
      local hunks = diff.compute_hunks(nil, 'a\nb\n')
      assert.are.equal(1, #hunks)
      assert.are.equal('add', hunks[1].kind)
      assert.are.equal(0, hunks[1].count_a)
      assert.are.equal(2, hunks[1].count_b)
    end)

    it('finds multiple independent hunks', function()
      local hunks = diff.compute_hunks('a\nb\nc\nd\ne\nf\ng\n', 'a\nB\nc\nd\ne\nF\ng\n')
      assert.are.equal(2, #hunks)
    end)
  end)

  describe('sign_rows', function()
    it('signs every added row for an add hunk', function()
      local rows = diff.sign_rows({ kind = 'add', start_a = 2, count_a = 0, start_b = 3, count_b = 2 })
      assert.are.same({ { row = 3, kind = 'add' }, { row = 4, kind = 'add' } }, rows)
    end)

    it('signs a single delete row, at start_b when not at the top', function()
      local rows = diff.sign_rows({ kind = 'delete', start_a = 3, count_a = 1, start_b = 2, count_b = 0 })
      assert.are.same({ { row = 2, kind = 'delete' } }, rows)
    end)

    it('signs row 1 as topdelete when start_b is 0', function()
      local rows = diff.sign_rows({ kind = 'delete', start_a = 1, count_a = 1, start_b = 0, count_b = 0 })
      assert.are.same({ { row = 1, kind = 'topdelete' } }, rows)
    end)

    it('signs every overlapping row change for an even change hunk', function()
      local rows = diff.sign_rows({ kind = 'change', start_a = 2, count_a = 1, start_b = 2, count_b = 1 })
      assert.are.same({ { row = 2, kind = 'change' } }, rows)
    end)

    it('signs extra rows add when the change hunk grew (count_b > count_a)', function()
      local rows = diff.sign_rows({ kind = 'change', start_a = 5, count_a = 1, start_b = 5, count_b = 2 })
      assert.are.same({ { row = 5, kind = 'change' }, { row = 6, kind = 'add' } }, rows)
    end)

    it('re-marks the last row changedelete when the change hunk shrank (count_a > count_b)', function()
      local rows = diff.sign_rows({ kind = 'change', start_a = 5, count_a = 3, start_b = 5, count_b = 1 })
      assert.are.same({ { row = 5, kind = 'changedelete' } }, rows)
    end)
  end)

  describe('build_patch', function()
    it('builds a minimal zero-context unified diff for one hunk', function()
      local indexed = { 'a', 'b', 'c' }
      local buffer = { 'a', 'B', 'c' }
      local hunk = { kind = 'change', start_a = 2, count_a = 1, start_b = 2, count_b = 1 }
      local patch = diff.build_patch('foo.txt', indexed, buffer, hunk)
      assert.are.same({
        'diff --git a/foo.txt b/foo.txt',
        '--- a/foo.txt',
        '+++ b/foo.txt',
        '@@ -2,1 +2,1 @@',
        '-b',
        '+B',
        '',
      }, vim.split(patch, '\n', { plain = true }))
    end)

    it('builds a pure-addition patch with zero removed lines', function()
      local hunk = { kind = 'add', start_a = 2, count_a = 0, start_b = 3, count_b = 1 }
      local patch = diff.build_patch('foo.txt', { 'a', 'b' }, { 'a', 'b', 'c' }, hunk)
      assert.matches('@@ %-2,0 %+3,1 @@\n%+c\n$', patch)
    end)
  end)
end)

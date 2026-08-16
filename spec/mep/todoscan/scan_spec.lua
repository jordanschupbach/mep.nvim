-- rg-backed paths are exercised by mocking vim.fn.jobstart/executable
-- directly (never a real subprocess) — the same approach
-- spec/mep/picker/sources/grep_spec.lua uses; see spec/README.md.
local scan = require('mep.todoscan.scan')

describe('mep.todoscan.scan', function()
  describe('match_line', function()
    local keywords = { 'TODO', 'FIXME', 'HACK', 'NOTE' }

    it('matches a bare keyword and returns its 0-indexed column span', function()
      local keyword, s, e = scan.match_line('-- TODO fix this', keywords)
      assert.are.equal('TODO', keyword)
      assert.are.equal(3, s)
      assert.are.equal(7, e)
    end)

    it('matches each of the default keywords', function()
      assert.are.equal('FIXME', (scan.match_line('# FIXME: broken', keywords)))
      assert.are.equal('HACK', (scan.match_line('// HACK around it', keywords)))
      assert.are.equal('NOTE', (scan.match_line('NOTE this', keywords)))
    end)

    it('does not match a keyword embedded in a longer word', function()
      assert.is_nil(scan.match_line('TODOLIST is not a match', keywords))
      assert.is_nil(scan.match_line('see MYTODO below', keywords))
    end)

    it('returns nil when nothing matches', function()
      assert.is_nil(scan.match_line('just a normal comment', keywords))
    end)

    it('returns the first-listed keyword when a line has more than one', function()
      local keyword = scan.match_line('TODO and also FIXME', keywords)
      assert.are.equal('TODO', keyword)
    end)

    it('respects a custom keyword list', function()
      assert.are.equal('XXX', (scan.match_line('XXX something', { 'XXX' })))
      assert.is_nil(scan.match_line('TODO something', { 'XXX' }))
    end)
  end)

  describe('scan', function()
    local orig_executable, orig_jobstart
    local captured

    before_each(function()
      orig_executable = vim.fn.executable
      orig_jobstart = vim.fn.jobstart
      captured = nil
    end)

    after_each(function()
      vim.fn.executable = orig_executable
      vim.fn.jobstart = orig_jobstart
    end)

    describe('with rg on PATH', function()
      before_each(function()
        vim.fn.executable = function(cmd)
          return cmd == 'rg' and 1 or 0
        end
        vim.fn.jobstart = function(cmd, jopts)
          captured = { cmd = cmd, opts = jopts }
          return 42
        end
      end)

      it('builds an rg --vimgrep call with a keyword-alternation pattern', function()
        scan.scan('/repo', { 'TODO', 'FIXME' }, function() end)
        assert.are.same(
          { 'rg', '--vimgrep', '--no-heading', '--color=never', '-e', '\\b(TODO|FIXME)\\b', '.' },
          captured.cmd
        )
        assert.are.equal('/repo', captured.opts.cwd)
      end)

      it('escapes regex metacharacters in a custom keyword', function()
        scan.scan('/repo', { 'C++' }, function() end)
        assert.are.same(
          { 'rg', '--vimgrep', '--no-heading', '--color=never', '-e', '\\b(C\\+\\+)\\b', '.' },
          captured.cmd
        )
      end)

      it('parses matching vimgrep output into items', function()
        local result
        scan.scan('/repo', { 'TODO', 'FIXME' }, function(items)
          result = items
        end)
        captured.opts.on_stdout(1, { 'lua/foo.lua:12:5:  -- TODO fix this', '' })
        captured.opts.on_exit(1, 0)

        assert.are.equal(1, #result)
        assert.are.same({
          filename = 'lua/foo.lua',
          lnum = 12,
          col = 5,
          keyword = 'TODO',
          text = '-- TODO fix this',
        }, result[1])
      end)

      it('ignores stdout lines that do not match the vimgrep format', function()
        local result
        scan.scan('/repo', { 'TODO' }, function(items)
          result = items
        end)
        captured.opts.on_stdout(1, { 'not a vimgrep line', '' })
        captured.opts.on_exit(1, 0)
        assert.are.same({}, result)
      end)

      it('parses multiple matches across separate lines', function()
        local result
        scan.scan('/repo', { 'TODO', 'FIXME' }, function(items)
          result = items
        end)
        captured.opts.on_stdout(1, {
          'a.lua:1:1:TODO first',
          'b.lua:2:1:FIXME second',
          '',
        })
        captured.opts.on_exit(1, 0)

        assert.are.equal(2, #result)
        assert.are.equal('TODO', result[1].keyword)
        assert.are.equal('FIXME', result[2].keyword)
      end)
    end)

    describe('without rg on PATH', function()
      local orig_scan_dir, orig_readfile

      before_each(function()
        vim.fn.executable = function()
          return 0
        end
        local core = require('mep.core')
        orig_scan_dir = core.util.scan_dir
        orig_readfile = vim.fn.readfile
      end)

      after_each(function()
        require('mep.core').util.scan_dir = orig_scan_dir
        vim.fn.readfile = orig_readfile
      end)

      it('falls back to a synchronous walk+grep, calling back immediately', function()
        local core = require('mep.core')
        core.util.scan_dir = function(cwd, items)
          items[#items + 1] = { filename = 'a.lua', display = 'a.lua' }
        end
        vim.fn.readfile = function(path)
          assert.are.equal('/repo/a.lua', path)
          return { 'first line', '-- TODO do the thing', 'last line' }
        end

        local result
        scan.scan('/repo', { 'TODO' }, function(items)
          result = items
        end)

        assert.are.equal(1, #result)
        assert.are.same({
          filename = 'a.lua',
          lnum = 2,
          col = 4,
          keyword = 'TODO',
          text = '-- TODO do the thing',
        }, result[1])
      end)

      it('skips a file it cannot read', function()
        local core = require('mep.core')
        core.util.scan_dir = function(cwd, items)
          items[#items + 1] = { filename = 'gone.lua', display = 'gone.lua' }
        end
        vim.fn.readfile = function()
          error('no such file')
        end

        local result
        assert.has_no.errors(function()
          scan.scan('/repo', { 'TODO' }, function(items)
            result = items
          end)
        end)
        assert.are.same({}, result)
      end)
    end)
  end)
end)

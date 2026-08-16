-- Both the git clone and the compile step go through core.job.spawn ->
-- vim.fn.jobstart, mocked here (never a real subprocess — see
-- spec/README.md). vim.treesitter.language.add is also mocked where
-- needed since we don't want tests depending on which parsers happen to
-- be bundled with the Neovim these specs run under.
local install = require('mep.treesitter.install')
local parsers = require('mep.treesitter.parsers')

local function mock_jobstart_capturing(sink)
  return function(cmd, jopts)
    local call = { cmd = cmd, opts = jopts }
    table.insert(sink, call)
    return #sink
  end
end

describe('mep.treesitter.install', function()
  local orig_jobstart, orig_executable, orig_language_add, orig_get_files
  local calls

  before_each(function()
    orig_jobstart = vim.fn.jobstart
    orig_executable = vim.fn.executable
    orig_language_add = vim.treesitter.language.add
    orig_get_files = vim.treesitter.query.get_files
    calls = {}
    vim.fn.jobstart = mock_jobstart_capturing(calls)
    vim.fn.executable = function()
      return 1
    end
    -- Queries "already present" by default in every test below that
    -- doesn't say otherwise, so `M.has_queries` (a second, independent
    -- gate alongside `is_available`) doesn't change any existing test's
    -- behavior — query-copying itself is covered by its own describe
    -- block further down, which overrides this per test.
    vim.treesitter.query.get_files = function()
      return { '/fake/queries/highlights.scm' }
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.executable = orig_executable
    vim.treesitter.language.add = orig_language_add
    vim.treesitter.query.get_files = orig_get_files
  end)

  describe('is_available', function()
    it('reflects vim.treesitter.language.add', function()
      vim.treesitter.language.add = function()
        return true
      end
      assert.is_true(install.is_available('whatever'))

      vim.treesitter.language.add = function()
        return nil, 'nope'
      end
      assert.is_false(install.is_available('whatever'))
    end)
  end)

  describe('has_queries', function()
    it('reflects vim.treesitter.query.get_files for a "highlights" query', function()
      vim.treesitter.query.get_files = function(lang, query_name)
        assert.are.equal('whatever', lang)
        assert.are.equal('highlights', query_name)
        return { '/some/path/highlights.scm' }
      end
      assert.is_true(install.has_queries('whatever'))

      vim.treesitter.query.get_files = function()
        return {}
      end
      assert.is_false(install.has_queries('whatever'))
    end)
  end)

  describe('install', function()
    it('fails immediately for a name not in the registry, without spawning anything', function()
      local result
      install.install('not-a-real-parser', function(ok, err)
        result = { ok = ok, err = err }
      end)
      assert.is_false(result.ok)
      assert.matches('not%-a%-real%-parser', result.err)
      assert.are.equal(0, #calls)
    end)

    it('succeeds immediately when already available, without spawning anything', function()
      vim.treesitter.language.add = function()
        return true
      end
      local result
      install.install('lua', function(ok)
        result = ok
      end)
      assert.is_true(result)
      assert.are.equal(0, #calls)
    end)

    it('fails gracefully when no C compiler is on PATH', function()
      vim.treesitter.language.add = function()
        return nil, 'not available'
      end
      vim.fn.executable = function(name)
        return name == 'git' and 1 or 0
      end
      local result
      install.install('lua', function(ok, err)
        result = { ok = ok, err = err }
      end)
      assert.is_false(result.ok)
      assert.matches('compiler', result.err)
      assert.are.equal(0, #calls)
    end)

    it('fails gracefully when git is not on PATH', function()
      vim.treesitter.language.add = function()
        return nil, 'not available'
      end
      vim.fn.executable = function(name)
        return name == 'cc' and 1 or 0
      end
      local result
      install.install('lua', function(ok, err)
        result = { ok = ok, err = err }
      end)
      assert.is_false(result.ok)
      assert.matches('git', result.err)
      assert.are.equal(0, #calls)
    end)

    describe('happy path', function()
      before_each(function()
        vim.treesitter.language.add = function()
          return nil, 'not available yet'
        end
      end)

      it('clones then compiles, and loads by explicit path on success', function()
        local result
        install.install('json', function(ok, err)
          result = { ok = ok, err = err }
        end)

        assert.are.equal(1, #calls)
        assert.are.equal('git', calls[1].cmd[1])
        assert.is_true(vim.tbl_contains(calls[1].cmd, parsers.registry.json.url))

        local load_calls = {}
        vim.treesitter.language.add = function(name, opts)
          table.insert(load_calls, { name = name, opts = opts })
          return true
        end
        calls[1].opts.on_exit(1, 0) -- git clone succeeds

        assert.are.equal(2, #calls)
        assert.are.equal('cc', calls[2].cmd[1])
        calls[2].opts.on_exit(1, 0) -- compile succeeds

        assert.is_true(result.ok)
        assert.are.equal(1, #load_calls)
        assert.are.equal('json', load_calls[1].name)
        assert.is_string(load_calls[1].opts.path)
      end)

      it('passes --branch when the registry entry pins one (sql)', function()
        install.install('sql', function() end)
        assert.is_true(vim.tbl_contains(calls[1].cmd, '--branch'))
        assert.is_true(vim.tbl_contains(calls[1].cmd, 'gh-pages'))
      end)

      it('builds source paths under the location subdirectory (typescript)', function()
        install.install('typescript', function() end)
        calls[1].opts.on_exit(1, 0)
        -- every file compiled should be rooted under .../typescript/src/
        for _, f in ipairs(calls[2].cmd) do
          if f:match('parser%.c$') or f:match('scanner%.c$') then
            assert.matches('/typescript/src/', f, 1, true)
          end
        end
      end)

      it('fails with a clear error when git clone fails', function()
        local result
        install.install('json', function(ok, err)
          result = { ok = ok, err = err }
        end)
        calls[1].opts.on_exit(1, 1) -- git clone fails
        assert.is_false(result.ok)
        assert.matches('git clone failed', result.err)
        assert.are.equal(1, #calls) -- compile never attempted
      end)

      it('fails with a clear error when compilation fails', function()
        local result
        install.install('json', function(ok, err)
          result = { ok = ok, err = err }
        end)
        calls[1].opts.on_exit(1, 0)
        calls[2].opts.on_stderr(1, { 'syntax error', '' })
        calls[2].opts.on_exit(1, 1)
        assert.is_false(result.ok)
        assert.matches('compile failed', result.err)
      end)

      it('fails when the compiled library cannot actually be loaded', function()
        local result
        install.install('json', function(ok, err)
          result = { ok = ok, err = err }
        end)
        calls[1].opts.on_exit(1, 0)
        vim.treesitter.language.add = function()
          return nil, 'incompatible ABI'
        end
        calls[2].opts.on_exit(1, 0)
        assert.is_false(result.ok)
        assert.matches('failed to load', result.err)
      end)
    end)

    describe('query copying', function()
      local config = require('mep.treesitter.config')
      local orig_query_dir, scratch_dir

      before_each(function()
        orig_query_dir = config.options.query_dir
        scratch_dir = vim.fn.tempname()
        config.options.query_dir = scratch_dir
      end)

      after_each(function()
        config.options.query_dir = orig_query_dir
        pcall(vim.fn.delete, scratch_dir, 'rf')
      end)

      --- Simulates the clone actually landing a queries/ dir at `tmpdir`
      --- (calls[1]'s own destination arg) — core.job.spawn is mocked
      --- (see spec/README.md), so nothing real ever runs; the "clone"
      --- has to be faked onto real disk for copy_queries' own real
      --- filesystem calls to find anything.
      local function fake_cloned_queries(lines)
        local tmpdir = calls[1].cmd[#calls[1].cmd]
        vim.fn.mkdir(tmpdir .. '/queries', 'p')
        vim.fn.writefile(lines or { '(identifier) @variable' }, tmpdir .. '/queries/highlights.scm')
        return tmpdir
      end

      it('fetches queries via a clone even when the parser is already available, without compiling', function()
        vim.treesitter.language.add = function()
          return true
        end
        vim.treesitter.query.get_files = function()
          return {}
        end

        local result
        install.install('json', function(ok, err)
          result = { ok = ok, err = err }
        end)

        assert.are.equal(1, #calls)
        assert.are.equal('git', calls[1].cmd[1])
        local tmpdir = fake_cloned_queries()
        calls[1].opts.on_exit(1, 0)

        assert.are.equal(1, #calls) -- no compile step
        assert.is_true(result.ok)
        assert.are.same({ '(identifier) @variable' }, vim.fn.readfile(scratch_dir .. '/json/highlights.scm'))
        assert.is_false(vim.fn.isdirectory(tmpdir) == 1) -- cleaned up
      end)

      it('copies queries/ alongside a freshly-compiled parser too', function()
        vim.treesitter.language.add = function()
          return nil, 'not available yet'
        end
        vim.treesitter.query.get_files = function()
          return {}
        end

        install.install('json', function() end)
        fake_cloned_queries({ '(pair) @field' })
        calls[1].opts.on_exit(1, 0) -- clone
        vim.treesitter.language.add = function()
          return true
        end
        calls[2].opts.on_exit(1, 0) -- compile

        assert.are.same({ '(pair) @field' }, vim.fn.readfile(scratch_dir .. '/json/highlights.scm'))
      end)

      it('does not touch query_dir when the cloned repo has no queries/ directory', function()
        vim.treesitter.language.add = function()
          return true
        end
        vim.treesitter.query.get_files = function()
          return {}
        end

        install.install('json', function() end)
        calls[1].opts.on_exit(1, 0) -- clone, no queries/ dir faked in

        assert.are.equal(0, vim.fn.isdirectory(scratch_dir .. '/json'))
      end)

      it('does not re-clone at all when both the parser and its queries are already available', function()
        vim.treesitter.language.add = function()
          return true
        end
        vim.treesitter.query.get_files = function()
          return { '/already/here/highlights.scm' }
        end

        local result
        install.install('json', function(ok)
          result = ok
        end)

        assert.is_true(result)
        assert.are.equal(0, #calls)
      end)
    end)
  end)

  describe('install_all', function()
    it('warns once and returns an empty result when compiler or git is missing, without spawning anything', function()
      vim.fn.executable = function()
        return 0
      end
      local orig_notify = vim.notify
      local notified = 0
      vim.notify = function()
        notified = notified + 1
      end

      local result
      install.install_all({ 'lua', 'python' }, nil, function(r)
        result = r
      end)

      vim.notify = orig_notify
      assert.are.equal(1, notified)
      assert.are.same({ installed = {}, skipped = {}, failed = {} }, result)
      assert.are.equal(0, #calls)
    end)

    it('reports already-available parsers as skipped, without spawning anything', function()
      vim.treesitter.language.add = function()
        return true
      end

      local result
      install.install_all({ 'lua', 'python' }, nil, function(r)
        result = r
      end)

      assert.are.same({ 'lua', 'python' }, result.skipped)
      assert.are.same({}, result.installed)
      assert.are.equal(0, #calls)
    end)

    it('reports an unknown name as failed rather than aborting the whole batch', function()
      vim.treesitter.language.add = function()
        return true
      end

      local result
      install.install_all({ 'lua', 'not-a-real-parser' }, nil, function(r)
        result = r
      end)

      assert.are.same({ 'lua' }, result.skipped)
      assert.is_not_nil(result.failed['not-a-real-parser'])
    end)

    it('calls on_progress for each parser', function()
      vim.treesitter.language.add = function()
        return true
      end

      local progressed = {}
      install.install_all({ 'lua', 'python' }, function(name, ok)
        table.insert(progressed, { name = name, ok = ok })
      end, function() end)

      assert.are.equal(2, #progressed)
    end)
  end)
end)

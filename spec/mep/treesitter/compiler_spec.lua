-- compile() goes through core.job.spawn -> vim.fn.jobstart; mocked here
-- the same way core/job_spec.lua and the picker sources' specs do, so no
-- real subprocess runs (see spec/README.md for why that matters).
local compiler = require('mep.treesitter.compiler')

describe('mep.treesitter.compiler', function()
  describe('find', function()
    local orig_executable

    before_each(function()
      orig_executable = vim.fn.executable
    end)

    after_each(function()
      vim.fn.executable = orig_executable
    end)

    it('prefers cc over gcc and clang', function()
      vim.fn.executable = function()
        return 1
      end
      assert.are.equal('cc', compiler.find())
    end)

    it('falls back to gcc when cc is missing', function()
      vim.fn.executable = function(name)
        return name == 'gcc' and 1 or 0
      end
      assert.are.equal('gcc', compiler.find())
    end)

    it('falls back to clang when cc and gcc are missing', function()
      vim.fn.executable = function(name)
        return name == 'clang' and 1 or 0
      end
      assert.are.equal('clang', compiler.find())
    end)

    it('returns nil when no compiler is found', function()
      vim.fn.executable = function()
        return 0
      end
      assert.is_nil(compiler.find())
    end)
  end)

  describe('shared_lib_ext', function()
    local orig_has

    before_each(function()
      orig_has = vim.fn.has
    end)

    after_each(function()
      vim.fn.has = orig_has
    end)

    it('is .dylib on mac', function()
      vim.fn.has = function(feat)
        return feat == 'mac' and 1 or 0
      end
      assert.are.equal('.dylib', compiler.shared_lib_ext())
    end)

    it('is .dll on win32', function()
      vim.fn.has = function(feat)
        return feat == 'win32' and 1 or 0
      end
      assert.are.equal('.dll', compiler.shared_lib_ext())
    end)

    it('is .so otherwise', function()
      vim.fn.has = function()
        return 0
      end
      assert.are.equal('.so', compiler.shared_lib_ext())
    end)
  end)

  describe('compile', function()
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

    it('builds a shared-library compile command with the include dir and source files', function()
      compiler.compile('cc', {
        source_files = { '/tmp/x/src/parser.c', '/tmp/x/src/scanner.c' },
        include_dir = '/tmp/x/src',
        output_path = '/out/lua.so',
      }, function() end)

      assert.are.same({
        'cc',
        '-shared',
        '-fPIC',
        '-O2',
        '-o',
        '/out/lua.so',
        '-I',
        '/tmp/x/src',
        '/tmp/x/src/parser.c',
        '/tmp/x/src/scanner.c',
      }, captured.cmd)
    end)

    it('calls on_done(true) when the compiler exits 0', function()
      local result
      compiler.compile('cc', { source_files = {}, include_dir = '.', output_path = 'out.so' }, function(ok, err)
        result = { ok = ok, err = err }
      end)
      captured.opts.on_exit(1, 0)
      assert.is_true(result.ok)
      assert.is_nil(result.err)
    end)

    it('calls on_done(false, stderr) when the compiler exits non-zero', function()
      local result
      compiler.compile('cc', { source_files = {}, include_dir = '.', output_path = 'out.so' }, function(ok, err)
        result = { ok = ok, err = err }
      end)
      captured.opts.on_stderr(1, { 'error: something broke', '' })
      captured.opts.on_exit(1, 1)
      assert.is_false(result.ok)
      assert.are.equal('error: something broke', result.err)
    end)
  end)
end)

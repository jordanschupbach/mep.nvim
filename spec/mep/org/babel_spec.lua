local babel = require('mep.org.babel')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.babel', function()
  describe('find_blocks / at_cursor', function()
    it('parses a block\'s language, args, and body', function()
      local buf = make_buf({
        '* Task',
        '#+begin_src python :results output',
        'print("hi")',
        '#+end_src',
      })
      local blocks = babel.find_blocks(buf)
      assert.are.equal(1, #blocks)
      local b = blocks[1]
      assert.are.equal(2, b.start_lnum)
      assert.are.equal(4, b.end_lnum)
      assert.are.equal('python', b.lang)
      assert.are.equal(':results output', b.args)
      assert.are.same({ 'print("hi")' }, b.body)
    end)

    it('is case-insensitive on begin_src/end_src', function()
      local buf = make_buf({ '#+BEGIN_SRC lua', 'x = 1', '#+END_SRC' })
      local blocks = babel.find_blocks(buf)
      assert.are.equal(1, #blocks)
      assert.are.equal('lua', blocks[1].lang)
    end)

    it('finds multiple blocks in one buffer', function()
      local buf = make_buf({
        '#+begin_src lua', 'a', '#+end_src',
        '#+begin_src python', 'b', '#+end_src',
      })
      local blocks = babel.find_blocks(buf)
      assert.are.equal(2, #blocks)
      assert.are.equal('lua', blocks[1].lang)
      assert.are.equal('python', blocks[2].lang)
    end)

    it('skips an unterminated block', function()
      local buf = make_buf({ '#+begin_src lua', 'a = 1' })
      assert.are.same({}, babel.find_blocks(buf))
    end)

    it('at_cursor finds the block containing any line from begin to end, inclusive', function()
      local buf = make_buf({ 'x', '#+begin_src lua', 'a', 'b', '#+end_src', 'y' })
      assert.is_not_nil(babel.at_cursor(buf, 2))
      assert.is_not_nil(babel.at_cursor(buf, 3))
      assert.is_not_nil(babel.at_cursor(buf, 5))
      assert.is_nil(babel.at_cursor(buf, 1))
      assert.is_nil(babel.at_cursor(buf, 6))
    end)
  end)

  describe('parse_header_args', function()
    it('parses results and multiple var occurrences', function()
      local args = babel.parse_header_args(':results value :var x=1 :var y=hello')
      assert.are.equal('value', args.results)
      assert.are.same({ 'x=1', 'y=hello' }, args.var)
    end)

    it('parses a tangle target', function()
      local args = babel.parse_header_args(':tangle out.lua')
      assert.are.equal('out.lua', args.tangle)
    end)

    it('returns an empty var list and no other keys for an empty string', function()
      local args = babel.parse_header_args('')
      assert.are.same({}, args.var)
      assert.is_nil(args.results)
    end)

    it('returns an empty var list for nil', function()
      assert.are.same({ var = {} }, babel.parse_header_args(nil))
    end)

    it('keeps colons inside a value intact (e.g. a Rust use-path)', function()
      local args = babel.parse_header_args(':includes std::collections::HashMap :results output')
      assert.are.equal('std::collections::HashMap', args.includes)
      assert.are.equal('output', args.results)
    end)
  end)

  describe('render_results / insert_or_update_results', function()
    it('renders empty output as a bare #+RESULTS: line', function()
      assert.are.same({ '#+RESULTS:' }, babel.render_results({}))
    end)

    it('renders single-line output with a colon prefix', function()
      assert.are.same({ '#+RESULTS:', ': 42' }, babel.render_results({ '42' }))
    end)

    it('renders multi-line output as an example block', function()
      assert.are.same(
        { '#+RESULTS:', '#+begin_example', 'a', 'b', '#+end_example' },
        babel.render_results({ 'a', 'b' })
      )
    end)

    it('inserts a new results block right after end_lnum', function()
      local buf = make_buf({ '#+begin_src lua', 'x', '#+end_src', 'next line' })
      babel.insert_or_update_results(buf, 3, { 'out' })
      assert.are.same(
        { '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': out', 'next line' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('replaces an existing single-line results block', function()
      local buf = make_buf({ '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': old', 'next' })
      babel.insert_or_update_results(buf, 3, { 'new' })
      assert.are.same(
        { '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': new', 'next' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('replaces an existing example-block results block', function()
      local buf = make_buf({
        '#+begin_src lua', 'x', '#+end_src',
        '#+RESULTS:', '#+begin_example', 'a', 'b', '#+end_example', 'next',
      })
      babel.insert_or_update_results(buf, 3, { 'solo' })
      assert.are.same(
        { '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': solo', 'next' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('replaces an existing empty results block', function()
      local buf = make_buf({ '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', 'next' })
      babel.insert_or_update_results(buf, 3, { 'out' })
      assert.are.same(
        { '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': out', 'next' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('does not disturb unrelated content that is not a results block', function()
      local buf = make_buf({ '#+begin_src lua', 'x', '#+end_src', 'not results' })
      babel.insert_or_update_results(buf, 3, { 'out' })
      assert.are.same(
        { '#+begin_src lua', 'x', '#+end_src', '#+RESULTS:', ': out', 'not results' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)
  end)

  describe('find_results', function()
    it('finds a one-line result', function()
      local buf = make_buf({ 'before', '#+RESULTS:', ': 42', 'after' })
      assert.are.same({ { start_lnum = 2, end_lnum = 3 } }, babel.find_results(buf))
    end)

    it('finds an example-block result, spanning its own delimiters', function()
      local buf = make_buf({ '#+RESULTS:', '#+begin_example', 'a', 'b', '#+end_example', 'after' })
      assert.are.same({ { start_lnum = 1, end_lnum = 5 } }, babel.find_results(buf))
    end)

    it('finds an empty result as just the #+RESULTS: line', function()
      local buf = make_buf({ '#+RESULTS:', 'after' })
      assert.are.same({ { start_lnum = 1, end_lnum = 1 } }, babel.find_results(buf))
    end)

    it('finds every results block in the buffer, independent of any src block', function()
      local buf = make_buf({
        '#+RESULTS:', ': a',
        'unrelated text',
        '#+RESULTS:', ': b',
      })
      assert.are.same(
        { { start_lnum = 1, end_lnum = 2 }, { start_lnum = 4, end_lnum = 5 } },
        babel.find_results(buf)
      )
    end)

    it('returns an empty list when there are no results blocks', function()
      local buf = make_buf({ 'plain text', 'more plain text' })
      assert.are.same({}, babel.find_results(buf))
    end)
  end)

  describe('resolve_executable', function()
    it('returns the primary executable when available', function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        return name == 'python3' and 1 or 0
      end
      assert.are.equal('python3', babel.resolve_executable(babel.languages.python))
      vim.fn.executable = orig
    end)

    it('falls back to the secondary executable', function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        return name == 'python' and 1 or 0
      end
      assert.are.equal('python', babel.resolve_executable(babel.languages.python))
      vim.fn.executable = orig
    end)

    it('returns nil when neither is available', function()
      local orig = vim.fn.executable
      vim.fn.executable = function()
        return 0
      end
      assert.is_nil(babel.resolve_executable(babel.languages.python))
      vim.fn.executable = orig
    end)
  end)

  describe('execute', function()
    local orig_jobstart, orig_executable, orig_notify
    local captured_cmd, captured_opts
    local notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      notifications = {}
      captured_cmd, captured_opts = nil, nil
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return (name == 'lua' or name == 'python3' or name == 'bash') and 1 or 0
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
      vim.notify = orig_notify
    end)

    it('warns and does nothing without a source block at the cursor', function()
      local buf = make_buf({ 'no block here' })
      babel.execute(buf, 1)
      assert.are.equal(1, #notifications)
      assert.matches('no source block', notifications[1].msg)
    end)

    it('warns on an unsupported language', function()
      local buf = make_buf({ '#+begin_src cobol', 'x', '#+end_src' })
      babel.execute(buf, 1)
      assert.matches('unsupported babel language', notifications[1].msg)
    end)

    it('warns when no interpreter is found on PATH', function()
      vim.fn.executable = function()
        return 0
      end
      local buf = make_buf({ '#+begin_src lua', 'x', '#+end_src' })
      babel.execute(buf, 1)
      assert.matches('no lua interpreter found', notifications[1].msg)
    end)

    it('spawns the interpreter against a written temp script', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('lua', captured_cmd[1])
      assert.is_true(vim.fn.filereadable(captured_cmd[2]) == 1)
      assert.are.same({ 'print(1)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('injects :var bindings as a prelude before the body', function()
      local buf = make_buf({ '#+begin_src lua :var x=5', 'print(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'local x = 5', 'print(x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('quotes a non-numeric :var value as a string literal', function()
      local buf = make_buf({ '#+begin_src lua :var name=hi', 'print(name)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'local name = "hi"', 'print(name)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it(':results value wraps only the trailing non-blank line in print()', function()
      local buf = make_buf({ '#+begin_src lua :results value', 'local y = 2', 'y + 1', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'local y = 2', 'print(y + 1)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('inserts the captured stdout into a #+RESULTS: block on exit', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src', 'after' })
      babel.execute(buf, 1)
      local path = captured_cmd[2]

      captured_opts.on_stdout(42, { '1', '' })
      captured_opts.on_exit(42, 0)

      assert.are.same(
        { '#+begin_src lua', 'print(1)', '#+end_src', '#+RESULTS:', ': 1', 'after' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.are.equal(0, #notifications)
      assert.are.equal(0, vim.fn.filereadable(path))
    end)

    it('replaces an existing #+RESULTS: block on re-execution', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src', '#+RESULTS:', ': old' })
      babel.execute(buf, 1)
      captured_opts.on_stdout(42, { '2', '' })
      captured_opts.on_exit(42, 0)
      assert.are.same(
        { '#+begin_src lua', 'print(1)', '#+end_src', '#+RESULTS:', ': 2' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('still writes captured stdout and warns on a nonzero exit code', function()
      local buf = make_buf({ '#+begin_src lua', 'error("boom")', '#+end_src' })
      babel.execute(buf, 1)
      captured_opts.on_stderr(42, { 'boom', '' })
      captured_opts.on_exit(42, 1)
      assert.are.same(
        { '#+begin_src lua', 'error("boom")', '#+end_src', '#+RESULTS:' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.are.equal(1, #notifications)
      assert.matches('babel execution failed', notifications[1].msg)
      assert.matches('boom', notifications[1].msg)
    end)

    it('calls on_done with the exit code and captured output', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      local done_code, done_stdout
      babel.execute(buf, 1, function(code, stdout)
        done_code, done_stdout = code, stdout
      end)
      captured_opts.on_stdout(42, { '1', '' })
      captured_opts.on_exit(42, 0)
      assert.are.equal(0, done_code)
      assert.are.same({ '1' }, done_stdout)
    end)
  end)

  describe('run_sync', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return name == 'lua' and 1 or 0
      end
      -- Resolves synchronously — `M.run_sync` blocks on `vim.wait` until
      -- its own callback marks the run done, so (per spec/README.md's
      -- mocking convention for anything touching vim.fn.jobstart) the
      -- callbacks fire from inside the mock itself, before it returns,
      -- rather than being driven by hand afterwards the way `M.execute`'s
      -- own (genuinely async) tests do.
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        opts.on_stdout(1, { '1', '' })
        opts.on_exit(1, 0)
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('runs the block and returns code/stdout/stderr synchronously', function()
      local code, stdout, stderr = babel.run_sync('lua', { var = {} }, { 'print(1)' })
      assert.are.equal(0, code)
      assert.are.same({ '1' }, stdout)
      assert.are.same({}, stderr)
      assert.are.equal('lua', captured_cmd[1])
    end)

    it('applies :var/:results value the same way M.execute does', function()
      -- Read the script inside the mock itself, before on_exit's own
      -- cleanup deletes it — unlike M.execute's tests, on_exit fires
      -- synchronously here (see this describe block's own before_each
      -- comment), so nothing survives past the `run_sync` call to
      -- inspect afterwards.
      local written
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        written = vim.fn.readfile(cmd[2])
        opts.on_stdout(1, { '1', '' })
        opts.on_exit(1, 0)
        return 1
      end
      babel.run_sync('lua', { var = { 'x=5' }, results = 'value' }, { 'local y = 2', 'y + 1' })
      assert.are.same({ 'local x = 5', 'local y = 2', 'print(y + 1)' }, written)
    end)

    it('returns nil, err for an unsupported language without spawning anything', function()
      local code, err = babel.run_sync('cobol', { var = {} }, { 'x' })
      assert.is_nil(code)
      assert.matches('unsupported babel language', err)
      assert.is_nil(captured_cmd)
    end)

    it('returns nil, err when no interpreter is found on PATH', function()
      vim.fn.executable = function()
        return 0
      end
      local code, err = babel.run_sync('lua', { var = {} }, { 'x' })
      assert.is_nil(code)
      assert.matches('no lua interpreter found', err)
    end)
  end)

  describe('cache (:cache yes)', function()
    local orig_jobstart, orig_executable, orig_notify
    local spawn_count
    local captured_opts
    local notifications

    before_each(function()
      babel.results_cache = {}
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      notifications = {}
      spawn_count = 0
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'lua' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        spawn_count = spawn_count + 1
        captured_opts = opts
        return spawn_count
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
      babel.results_cache = {}
    end)

    it('executes normally (spawns a job) without :cache', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal(1, spawn_count)
    end)

    it('a cache miss executes and stores the result on success', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal(1, spawn_count)
      captured_opts.on_stdout(1, { '1', '' })
      captured_opts.on_exit(1, 0)

      local block = babel.at_cursor(buf, 1)
      local key = babel.cache_key(buf, block)
      assert.are.same({ '1' }, babel.results_cache[key])
    end)

    it('a cache hit skips core.job.spawn entirely and reuses the cached output', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      captured_opts.on_stdout(1, { '1', '' })
      captured_opts.on_exit(1, 0)
      assert.are.equal(1, spawn_count)

      babel.execute(buf, 1)
      assert.are.equal(1, spawn_count) -- still 1: no second spawn

      assert.are.same(
        { '#+begin_src lua :cache yes', 'print(1)', '#+end_src', '#+RESULTS:', ': 1' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('calls on_done with code 0 and the cached output on a cache hit', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      captured_opts.on_stdout(1, { '1', '' })
      captured_opts.on_exit(1, 0)

      local done_code, done_stdout
      babel.execute(buf, 1, function(code, stdout)
        done_code, done_stdout = code, stdout
      end)
      assert.are.equal(0, done_code)
      assert.are.same({ '1' }, done_stdout)
    end)

    it('a failed run (nonzero exit) is never cached', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'error("boom")', '#+end_src' })
      babel.execute(buf, 1)
      captured_opts.on_stderr(1, { 'boom', '' })
      captured_opts.on_exit(1, 1)

      local block = babel.at_cursor(buf, 1)
      local key = babel.cache_key(buf, block)
      assert.is_nil(babel.results_cache[key])

      -- Re-executing spawns again rather than reusing anything.
      babel.execute(buf, 1)
      assert.are.equal(2, spawn_count)
    end)

    it('editing the block body invalidates the cache (different hash, re-executes)', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      captured_opts.on_stdout(1, { '1', '' })
      captured_opts.on_exit(1, 0)
      assert.are.equal(1, spawn_count)

      vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'print(2)' })
      babel.execute(buf, 1)
      assert.are.equal(2, spawn_count) -- re-executed: body changed, hash differs
    end)
  end)

  describe('compiled languages (cpp)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'g++' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('c++ and cpp both resolve to the same language definition', function()
      assert.are.equal(babel.languages.cpp, babel.languages['c++'])
    end)

    it('wraps the body in main() when the block sets :main yes, prepending :includes tokens as #include lines', function()
      local buf = make_buf({
        '#+begin_src c++ :main yes :includes <iostream>',
        'std::cout << "hi" << std::endl;',
        '#+end_src',
      })
      babel.execute(buf, 1)
      assert.are.equal(1, #calls)
      local compile_call = calls[1]
      assert.are.equal('g++', compile_call.cmd[1])
      assert.are.equal('-o', compile_call.cmd[3])
      local source_path = compile_call.cmd[2]
      assert.are.same({
        '#include <iostream>',
        'int main() {',
        'std::cout << "hi" << std::endl;',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('injects a :var binding as an auto prelude assignment before the body', function()
      local buf = make_buf({ '#+begin_src c++ :main yes :var x=5', 'std::cout << x;', '#+end_src' })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same(
        { 'int main() {', 'auto x = 5;', 'std::cout << x;', '  return 0;', '}' },
        vim.fn.readfile(source_path)
      )
      vim.fn.delete(source_path)
    end)

    it('on compile success, deletes the source and spawns the binary; on binary exit, writes results', function()
      local buf = make_buf({
        '#+begin_src c++ :includes <iostream>',
        'std::cout << "hi" << std::endl;',
        '#+end_src',
        'after',
      })
      babel.execute(buf, 1)
      local source_path, binary_path = calls[1].cmd[2], calls[1].cmd[4]

      calls[1].opts.on_exit(100, 0)
      assert.are.equal(0, vim.fn.filereadable(source_path))
      assert.are.equal(2, #calls)
      assert.are.same({ binary_path }, calls[2].cmd)

      calls[2].opts.on_stdout(101, { 'hi', '' })
      calls[2].opts.on_exit(101, 0)

      assert.are.same(
        { '#+begin_src c++ :includes <iostream>', 'std::cout << "hi" << std::endl;', '#+end_src', '#+RESULTS:', ': hi', 'after' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.are.equal(0, #notifications)
    end)

    it('warns and skips running the binary when compilation fails', function()
      local buf = make_buf({ '#+begin_src c++', 'not valid c++', '#+end_src' })
      babel.execute(buf, 1)
      calls[1].opts.on_stderr(100, { 'error: expected ...', '' })
      calls[1].opts.on_exit(100, 1)

      assert.are.equal(1, #calls)
      assert.are.equal(1, #notifications)
      assert.matches('babel compilation failed', notifications[1].msg)
      assert.matches('error: expected', notifications[1].msg)
      assert.are.same(
        { '#+begin_src c++', 'not valid c++', '#+end_src', '#+RESULTS:' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('warns and still deletes the binary when the compiled program exits nonzero', function()
      local buf = make_buf({ '#+begin_src c++', 'return 1;', '#+end_src' })
      babel.execute(buf, 1)
      local binary_path = calls[1].cmd[4]
      calls[1].opts.on_exit(100, 0)
      calls[2].opts.on_stderr(101, { 'boom', '' })
      calls[2].opts.on_exit(101, 1)

      assert.are.equal(1, #notifications)
      assert.matches('babel execution failed', notifications[1].msg)
      assert.matches('boom', notifications[1].msg)
      assert.are.equal(0, vim.fn.filereadable(binary_path))
    end)

    it('skips wrapping in main() when the block sets :main no', function()
      local buf = make_buf({
        '#+begin_src c++ :main no',
        '#include <iostream>',
        'int main() {',
        '  std::cout << "hi" << std::endl;',
        '  return 0;',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({
        '#include <iostream>',
        'int main() {',
        '  std::cout << "hi" << std::endl;',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src c++',
        '#include <iostream>',
        'int main() {',
        '  std::cout << "hi" << std::endl;',
        '  return 0;',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({
        '#include <iostream>',
        'int main() {',
        '  std::cout << "hi" << std::endl;',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (c)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'gcc' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('wraps the body in main() when the block sets :main yes, using gcc and a .c source file', function()
      local buf = make_buf({
        '#+begin_src c :main yes :includes <stdio.h>',
        'printf("hi\\n");',
        '#+end_src',
      })
      babel.execute(buf, 1)
      assert.are.equal(1, #calls)
      local compile_call = calls[1]
      assert.are.equal('gcc', compile_call.cmd[1])
      local source_path = compile_call.cmd[2]
      assert.matches('%.c$', source_path)
      assert.are.same({
        '#include <stdio.h>',
        'int main() {',
        'printf("hi\\n");',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('skips wrapping in main() when the block sets :main no', function()
      local buf = make_buf({
        '#+begin_src c :main no',
        '#include <stdio.h>',
        'int main() {',
        '  printf("hi\\n");',
        '  return 0;',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({
        '#include <stdio.h>',
        'int main() {',
        '  printf("hi\\n");',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src c',
        '#include <stdio.h>',
        'int main() {',
        '  printf("hi\\n");',
        '  return 0;',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({
        '#include <stdio.h>',
        'int main() {',
        '  printf("hi\\n");',
        '  return 0;',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('additional interpreted languages (ruby, perl, r, php)', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return (name == 'ruby' or name == 'perl' or name == 'Rscript' or name == 'php') and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('spawns ruby against a written temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src ruby :var x=5', 'puts(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('ruby', captured_cmd[1])
      assert.are.same({ 'x = 5', 'puts(x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('renders a ruby :results value expression through puts()', function()
      local buf = make_buf({ '#+begin_src ruby :results value', '1 + 1', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'puts(1 + 1)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns perl against a written temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src perl :var x=5', 'print($x, "\\n");', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('perl', captured_cmd[1])
      assert.are.same({ 'my $x = 5;', 'print($x, "\\n");' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns Rscript for an "r" language block with a :var prelude', function()
      local buf = make_buf({ '#+begin_src r :var x=5', 'print(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('Rscript', captured_cmd[1])
      assert.are.same({ 'x <- 5', 'print(x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('is case-insensitive on the "R" language tag', function()
      local buf = make_buf({ '#+begin_src R', 'print(1)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('Rscript', captured_cmd[1])
      vim.fn.delete(captured_cmd[2])
    end)

    it('wraps a php block in a leading <?php tag with a :var prelude', function()
      local buf = make_buf({ '#+begin_src php :var x=5', 'echo $x;', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('php', captured_cmd[1])
      assert.are.same({ '<?php', '$x = 5;', 'echo $x;' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('skips the <?php wrap when the php block sets :main no', function()
      local buf = make_buf({ '#+begin_src php :main no', '<?php echo "hi";', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ '<?php echo "hi";' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)
  end)

  describe('additional interpreted languages (typescript, elixir, julia, clojure)', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return (name == 'bun' or name == 'elixir' or name == 'julia' or name == 'bb') and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('spawns bun against a written .ts temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src typescript :var x=5', 'console.log(x);', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('bun', captured_cmd[1])
      assert.matches('%.ts$', captured_cmd[2])
      assert.are.same({ 'const x = 5;', 'console.log(x);' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('the "ts" alias resolves to the same typescript language def', function()
      assert.are.equal(babel.languages.typescript, babel.languages.ts)
    end)

    it('renders a typescript :results value expression through console.log()', function()
      local buf = make_buf({ '#+begin_src ts :results value', '1 + 1', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'console.log(1 + 1);' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns elixir against a written .exs temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src elixir :var x=5', 'IO.puts(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('elixir', captured_cmd[1])
      assert.matches('%.exs$', captured_cmd[2])
      assert.are.same({ 'x = 5', 'IO.puts(x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns julia against a written .jl temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src julia :var x=5', 'println(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('julia', captured_cmd[1])
      assert.matches('%.jl$', captured_cmd[2])
      assert.are.same({ 'x = 5', 'println(x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns bb (babashka) against a written .clj temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src clojure :var x=5', '(println x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('bb', captured_cmd[1])
      assert.matches('%.clj$', captured_cmd[2])
      assert.are.same({ '(def x 5)', '(println x)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('falls back to the clojure CLI when bb is unavailable', function()
      vim.fn.executable = function(name)
        return name == 'clojure' and 1 or 0
      end
      local buf = make_buf({ '#+begin_src clojure', '(println "hi")', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('clojure', captured_cmd[1])
      vim.fn.delete(captured_cmd[2])
    end)
  end)

  describe('csharp (via dotnet run, no wrap_main needed)', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return name == 'dotnet' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('spawns "dotnet run <file>", subcommand before the file', function()
      local buf = make_buf({ '#+begin_src csharp :var x=5', 'Console.WriteLine(x);', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'dotnet', 'run' }, { captured_cmd[1], captured_cmd[2] })
      local source_path = captured_cmd[3]
      assert.matches('%.cs$', source_path)
      assert.are.same({ 'var x = 5;', 'Console.WriteLine(x);' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap the body — top-level statements run as-is', function()
      local buf = make_buf({ '#+begin_src csharp', 'Console.WriteLine("hi");', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'Console.WriteLine("hi");' }, vim.fn.readfile(captured_cmd[3]))
      vim.fn.delete(captured_cmd[3])
    end)

    it('the "cs" and "c#" aliases resolve to the same csharp language def', function()
      assert.are.equal(babel.languages.csharp, babel.languages.cs)
      assert.are.equal(babel.languages.csharp, babel.languages['c#'])
    end)
  end)

  describe('compiled languages (fortran)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'gfortran' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('appends a bare "end" when the block sets :main yes', function()
      local buf = make_buf({ '#+begin_src fortran :main yes', 'print *, "hi"', '#+end_src' })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.matches('%.f90$', source_path)
      assert.are.same({ 'print *, "hi"', 'end' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src fortran',
        'program hello',
        '  print *, "hi"',
        'end program hello',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same(
        { 'program hello', '  print *, "hi"', 'end program hello' },
        vim.fn.readfile(source_path)
      )
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (scala)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'scala' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('wraps the body in an indented @main def when the block sets :main yes', function()
      local buf = make_buf({ '#+begin_src scala :main yes', 'println("hi")', '#+end_src' })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.matches('%.scala$', source_path)
      assert.are.same({ '@main def run(): Unit =', '  println("hi")' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src scala',
        '@main def run(): Unit =',
        '  println("hi")',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({ '@main def run(): Unit =', '  println("hi")' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (rust)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'rustc' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('wraps the body in fn main() when the block sets :main yes, prepending :includes tokens as use statements', function()
      local buf = make_buf({
        '#+begin_src rust :main yes :includes std::collections::HashMap',
        'println!("hi");',
        '#+end_src',
      })
      babel.execute(buf, 1)
      assert.are.equal(1, #calls)
      local compile_call = calls[1]
      assert.are.equal('rustc', compile_call.cmd[1])
      assert.are.equal('-o', compile_call.cmd[3])
      local source_path = compile_call.cmd[2]
      assert.are.same({
        'use std::collections::HashMap;',
        'fn main() {',
        'println!("hi");',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('on compile success, runs the binary and writes its output as results', function()
      local buf = make_buf({ '#+begin_src rust :main yes', 'println!("hi");', '#+end_src', 'after' })
      babel.execute(buf, 1)
      local binary_path = calls[1].cmd[4]
      calls[1].opts.on_exit(100, 0)
      assert.are.equal(2, #calls)
      assert.are.same({ binary_path }, calls[2].cmd)
      calls[2].opts.on_stdout(101, { 'hi', '' })
      calls[2].opts.on_exit(101, 0)
      assert.are.same(
        { '#+begin_src rust :main yes', 'println!("hi");', '#+end_src', '#+RESULTS:', ': hi', 'after' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.are.equal(0, #notifications)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src rust',
        'fn main() {',
        '  println!("hi");',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[2]
      assert.are.same({ 'fn main() {', '  println!("hi");', '}' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (go)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'go' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('compiles with "go build -o <bin> <src>", subcommand before flags', function()
      local buf = make_buf({
        '#+begin_src go :main yes :includes fmt',
        'fmt.Println("hi")',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local compile_call = calls[1]
      assert.are.same({ 'go', 'build', '-o' }, { compile_call.cmd[1], compile_call.cmd[2], compile_call.cmd[3] })
      local binary_path = compile_call.cmd[4]
      local source_path = compile_call.cmd[5]
      assert.are.same({
        'package main',
        '',
        'import (',
        '\t"fmt"',
        ')',
        '',
        'func main() {',
        'fmt.Println("hi")',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)

      calls[1].opts.on_exit(100, 0)
      assert.are.same({ binary_path }, calls[2].cmd)
    end)

    it('wraps with an empty import block when there are no :includes', function()
      local buf = make_buf({ '#+begin_src go :main yes', 'x := 1', '_ = x', '#+end_src' })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[5]
      assert.are.same(
        { 'package main', '', 'import (', ')', '', 'func main() {', 'x := 1', '_ = x', '}' },
        vim.fn.readfile(source_path)
      )
      vim.fn.delete(source_path)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src go',
        'package main',
        '',
        'import "fmt"',
        '',
        'func main() {',
        '\tfmt.Println("hi")',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[5]
      assert.are.same(
        { 'package main', '', 'import "fmt"', '', 'func main() {', '\tfmt.Println("hi")', '}' },
        vim.fn.readfile(source_path)
      )
      vim.fn.delete(source_path)
    end)

    it('surfaces the real compiler error, not just the leading "# command-line-arguments" package header', function()
      local buf = make_buf({ '#+begin_src go', 'fmt.Println("hi")', '#+end_src' })
      babel.execute(buf, 1)
      calls[1].opts.on_stderr(100, { '# command-line-arguments', './main.go:1:1: undefined: fmt', '' })
      calls[1].opts.on_exit(100, 2)

      assert.are.equal(1, #notifications)
      assert.matches('babel compilation failed', notifications[1].msg)
      assert.matches('undefined: fmt', notifications[1].msg)
    end)
  end)

  describe('single-command "run" languages (zig, nim, crystal)', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return (name == 'zig' or name == 'nim' or name == 'crystal') and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('spawns "zig run <file>", subcommand before the file, wrapping a bare body in main()', function()
      local buf = make_buf({ '#+begin_src zig :main yes', 'try stdout.writeAll("hi\\n");', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'zig', 'run' }, { captured_cmd[1], captured_cmd[2] })
      local source_path = captured_cmd[3]
      assert.matches('%.zig$', source_path)
      assert.are.same({
        'const std = @import("std");',
        'pub fn main(init: std.process.Init) !void {',
        '  var stdout_buffer: [4096]u8 = undefined;',
        '  var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);',
        '  const stdout = &stdout_writer.interface;',
        'try stdout.writeAll("hi\\n");',
        '  try stdout.flush();',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap a zig block by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src zig',
        'const std = @import("std");',
        'pub fn main() !void {}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      assert.are.same({ 'const std = @import("std");', 'pub fn main() !void {}' }, vim.fn.readfile(captured_cmd[3]))
      vim.fn.delete(captured_cmd[3])
    end)

    it('spawns "nim r <file>" against a valid-identifier-named copy of the written script', function()
      local buf = make_buf({ '#+begin_src nim :var x=5', 'echo x', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'nim', 'r', '--hints:off', '--warnings:off' }, { captured_cmd[1], captured_cmd[2], captured_cmd[3], captured_cmd[4] })
      local run_path = captured_cmd[5]
      -- the file nim actually runs is a sibling of the real temp script,
      -- renamed with a leading letter (nim's own module-name validation
      -- rejects a purely numeric basename) — see M.languages.nim's own
      -- comment for why
      assert.matches('/m[^/]*%.nim$', run_path)
      assert.are.same({ 'let x = 5', 'echo x' }, vim.fn.readfile(run_path))
      vim.fn.delete(run_path)
    end)

    it('does not wrap a nim block — top-level statements run as-is', function()
      local buf = make_buf({ '#+begin_src nim', 'echo "hi"', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'echo "hi"' }, vim.fn.readfile(captured_cmd[5]))
      vim.fn.delete(captured_cmd[5])
    end)

    it('spawns "crystal run <file>", subcommand before the file, with no wrapping', function()
      local buf = make_buf({ '#+begin_src crystal :var x=5', 'puts x', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'crystal', 'run' }, { captured_cmd[1], captured_cmd[2] })
      local source_path = captured_cmd[3]
      assert.matches('%.cr$', source_path)
      assert.are.same({ 'x = 5', 'puts x' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (java)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'javac' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('compiles with "javac -d <dir> <src>", wrapping a bare body in a package-private Main class', function()
      local buf = make_buf({ '#+begin_src java :main yes', 'System.out.println("hi");', '#+end_src' })
      babel.execute(buf, 1)
      local compile_call = calls[1]
      assert.are.same({ 'javac', '-d' }, { compile_call.cmd[1], compile_call.cmd[2] })
      local binary_path = compile_call.cmd[3]
      local source_path = compile_call.cmd[4]
      assert.are.same({
        'class Main {',
        '  public static void main(String[] args) {',
        '    System.out.println("hi");',
        '  }',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)

      calls[1].opts.on_exit(100, 0)
      assert.are.same({ 'java', '-cp', binary_path, 'Main' }, calls[2].cmd)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src java',
        'class Main {',
        '  public static void main(String[] args) {}',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[4]
      assert.are.same({ 'class Main {', '  public static void main(String[] args) {}', '}' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('prepends :includes tokens as import lines', function()
      local buf = make_buf({ '#+begin_src java :main yes :includes java.util.List', 'List.of();', '#+end_src' })
      babel.execute(buf, 1)
      local source_path = calls[1].cmd[4]
      assert.are.same({
        'import java.util.List;',
        'class Main {',
        '  public static void main(String[] args) {',
        '    List.of();',
        '  }',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('renames a self-contained public class to <ClassName>.java and runs that class', function()
      local buf = make_buf({
        '#+begin_src java',
        'public class HelloWorld {',
        '  public static void main(String[] args) {',
        '    System.out.println("hi");',
        '  }',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local compile_call = calls[1]
      local binary_path = compile_call.cmd[3]
      local source_path = compile_call.cmd[4]
      assert.matches('/HelloWorld%.java$', source_path)
      assert.are.same({
        'public class HelloWorld {',
        '  public static void main(String[] args) {',
        '    System.out.println("hi");',
        '  }',
        '}',
      }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)

      calls[1].opts.on_exit(100, 0)
      assert.are.same({ 'java', '-cp', binary_path, 'HelloWorld' }, calls[2].cmd)
    end)

    it(':classname overrides class detection', function()
      local buf = make_buf({
        '#+begin_src java :classname Other',
        'public class HelloWorld {',
        '  public static void main(String[] args) {}',
        '}',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local compile_call = calls[1]
      local binary_path = compile_call.cmd[3]
      local source_path = compile_call.cmd[4]
      assert.matches('/Other%.java$', source_path)
      vim.fn.delete(source_path)

      calls[1].opts.on_exit(100, 0)
      assert.are.same({ 'java', '-cp', binary_path, 'Other' }, calls[2].cmd)
    end)

    it('recursively deletes the class-file directory (not just a single binary) after the run finishes', function()
      local orig_delete = vim.fn.delete
      local deletes = {}
      vim.fn.delete = function(path, flags)
        deletes[#deletes + 1] = { path = path, flags = flags }
        return orig_delete(path, flags)
      end

      local buf = make_buf({ '#+begin_src java :main yes', 'System.out.println("hi");', '#+end_src' })
      babel.execute(buf, 1)
      local binary_path = calls[1].cmd[3]
      calls[1].opts.on_exit(100, 0)
      calls[2].opts.on_stdout('hi')
      calls[2].opts.on_exit(101, 0)

      vim.fn.delete = orig_delete

      local found_recursive_delete = false
      for _, d in ipairs(deletes) do
        if d.path == binary_path and d.flags == 'rf' then
          found_recursive_delete = true
        end
      end
      assert.is_true(found_recursive_delete)
    end)
  end)

  describe('single-command "run" languages (kotlin, haskell, ocaml)', function()
    local orig_jobstart, orig_executable
    local captured_cmd

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      captured_cmd = nil
      vim.fn.executable = function(name)
        return (name == 'kotlin' or name == 'runghc' or name == 'ocaml') and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        captured_cmd = cmd
        return 1
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('spawns "kotlin <file>.kts" against a written temp script with a :var prelude', function()
      local buf = make_buf({ '#+begin_src kotlin :var x=5', 'println(x)', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('kotlin', captured_cmd[1])
      local source_path = captured_cmd[2]
      assert.matches('%.kts$', source_path)
      assert.are.same({ 'val x = 5', 'println(x)' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('renders a kotlin :results value expression through println()', function()
      local buf = make_buf({ '#+begin_src kotlin :results value', '1 + 1', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'println(1 + 1)' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns "runghc <file>.hs", wrapping a bare body in a "main = do" block when :main yes', function()
      local buf = make_buf({ '#+begin_src haskell :main yes', 'putStrLn "hi"', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('runghc', captured_cmd[1])
      local source_path = captured_cmd[2]
      assert.matches('%.hs$', source_path)
      assert.are.same({ 'main = do', '  putStrLn "hi"' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)

    it('does not wrap a haskell block by default, with no :main header arg at all', function()
      local buf = make_buf({ '#+begin_src haskell', 'main = putStrLn "hi"', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same({ 'main = putStrLn "hi"' }, vim.fn.readfile(captured_cmd[2]))
      vim.fn.delete(captured_cmd[2])
    end)

    it('prepends :includes tokens as import lines when wrapping a haskell block', function()
      local buf = make_buf({ '#+begin_src haskell :main yes :includes Data.List', 'print (sort [3,1,2])', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.same(
        { 'import Data.List', 'main = do', '  print (sort [3,1,2])' },
        vim.fn.readfile(captured_cmd[2])
      )
      vim.fn.delete(captured_cmd[2])
    end)

    it('spawns "ocaml <file>.ml" against a written temp script, :var bindings terminated with ;;', function()
      local buf = make_buf({ '#+begin_src ocaml :var x=5', 'print_int x;;', '#+end_src' })
      babel.execute(buf, 1)
      assert.are.equal('ocaml', captured_cmd[1])
      local source_path = captured_cmd[2]
      assert.matches('%.ml$', source_path)
      assert.are.same({ 'let x = 5;;', 'print_int x;;' }, vim.fn.readfile(source_path))
      vim.fn.delete(source_path)
    end)
  end)

  describe('compiled languages (d)', function()
    local orig_jobstart, orig_executable, orig_notify
    local calls, notifications

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      orig_notify = vim.notify
      calls = {}
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
      vim.fn.executable = function(name)
        return name == 'dmd' and 1 or 0
      end
      vim.fn.jobstart = function(cmd, opts)
        table.insert(calls, { cmd = cmd, opts = opts })
        return 100 + #calls
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
    end)

    it('compiles with "dmd <src> -of=<bin>", wrapping a bare body in void main(), std.stdio always imported', function()
      local buf = make_buf({ '#+begin_src d :main yes', 'writeln("hi");', '#+end_src' })
      babel.execute(buf, 1)
      local compile_call = calls[1]
      assert.are.equal('dmd', compile_call.cmd[1])
      -- the file dmd actually compiles is a sibling of the real temp
      -- script, renamed with a leading letter (dmd's own module-name
      -- validation rejects a purely numeric basename, same as Nim) —
      -- see M.languages.d's own comment for why
      local run_path = compile_call.cmd[2]
      assert.matches('/m[^/]*%.d$', run_path)
      assert.matches('^%-of=', compile_call.cmd[3])
      local binary_path = compile_call.cmd[3]:sub(#'-of=' + 1)
      assert.are.same({ 'import std.stdio;', 'void main() {', 'writeln("hi");', '}' }, vim.fn.readfile(run_path))
      vim.fn.delete(run_path)

      calls[1].opts.on_exit(100, 0)
      assert.are.same({ binary_path }, calls[2].cmd)
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local buf = make_buf({
        '#+begin_src d',
        'import std.stdio;',
        'void main() { writeln("hi"); }',
        '#+end_src',
      })
      babel.execute(buf, 1)
      local run_path = calls[1].cmd[2]
      assert.are.same({ 'import std.stdio;', 'void main() { writeln("hi"); }' }, vim.fn.readfile(run_path))
      vim.fn.delete(run_path)
    end)

    it('injects a :var binding as an auto-typed prelude assignment before the body', function()
      local buf = make_buf({ '#+begin_src d :main yes :var x=5', 'writeln(x);', '#+end_src' })
      babel.execute(buf, 1)
      local run_path = calls[1].cmd[2]
      assert.are.same(
        { 'import std.stdio;', 'void main() {', 'auto x = 5;', 'writeln(x);', '}' },
        vim.fn.readfile(run_path)
      )
      vim.fn.delete(run_path)
    end)
  end)

  describe('tangle_target', function()
    it('returns nil when there is no :tangle arg', function()
      local block = { args = '' }
      assert.is_nil(babel.tangle_target(block, 0))
    end)

    it('returns nil for :tangle no', function()
      local block = { args = ':tangle no' }
      assert.is_nil(babel.tangle_target(block, 0))
    end)

    it('resolves a relative target against the buffer\'s directory', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, '/tmp/notes/journal.org')
      local block = { args = ':tangle out.lua' }
      assert.are.equal('/tmp/notes/out.lua', babel.tangle_target(block, buf))
    end)

    it('leaves an absolute target as-is', function()
      local block = { args = ':tangle /elsewhere/out.lua' }
      assert.are.equal('/elsewhere/out.lua', babel.tangle_target(block, 0))
    end)
  end)

  describe('tangle_block / tangle_buffer', function()
    local tmpdir

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)
    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('tangle_block writes the block body to its :tangle target', function()
      local target = tmpdir .. '/out.lua'
      local buf = make_buf({ '#+begin_src lua :tangle ' .. target, 'print(1)', '#+end_src' })
      babel.tangle_block(buf, 1)
      assert.are.same({ 'print(1)' }, vim.fn.readfile(target))
    end)

    it('tangle_block warns when the block has no :tangle target', function()
      local orig_notify = vim.notify
      local msg
      vim.notify = function(m)
        msg = m
      end
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babel.tangle_block(buf, 1)
      vim.notify = orig_notify
      assert.matches('no :tangle target', msg)
    end)

    it('tangle_buffer skips blocks with no :tangle target', function()
      local target = tmpdir .. '/out.lua'
      local buf = make_buf({
        '#+begin_src lua :tangle ' .. target, 'a', '#+end_src',
        '#+begin_src lua', 'b', '#+end_src',
      })
      local written = babel.tangle_buffer(buf)
      assert.are.same({ target }, written)
      assert.are.same({ 'a' }, vim.fn.readfile(target))
    end)

    it('tangle_buffer concatenates multiple blocks sharing one target, blank-line separated', function()
      local target = tmpdir .. '/out.lua'
      local buf = make_buf({
        '#+begin_src lua :tangle ' .. target, 'a', '#+end_src',
        '#+begin_src lua :tangle ' .. target, 'b', '#+end_src',
      })
      babel.tangle_buffer(buf)
      assert.are.same({ 'a', '', 'b' }, vim.fn.readfile(target))
    end)

    it('tangle_buffer creates parent directories for the target', function()
      local target = tmpdir .. '/nested/dir/out.lua'
      local buf = make_buf({ '#+begin_src lua :tangle ' .. target, 'a', '#+end_src' })
      babel.tangle_buffer(buf)
      assert.are.same({ 'a' }, vim.fn.readfile(target))
    end)
  end)
end)

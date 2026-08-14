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

    it('wraps the body in main(), prepending :includes tokens as #include lines', function()
      local buf = make_buf({
        '#+begin_src c++ :includes <iostream>',
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
      local buf = make_buf({ '#+begin_src c++ :var x=5', 'std::cout << x;', '#+end_src' })
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

local tests_mod = require('mep.activitybar.tests')
local config = require('mep.activitybar.config')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.tests', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    tests_mod._reset()
  end)

  after_each(function()
    tests_mod._reset()
    config.options = saved_config
  end)

  describe('parse_output', function()
    it('parses a clean-pass summary with no failures', function()
      local text = table.concat({
        '+++++++++++++',
        '13 successes / 0 failures / 0 errors / 0 pending : 0.003975 seconds',
      }, '\n')
      local r = tests_mod.parse_output(text)
      assert.are.equal(13, r.successes)
      assert.are.equal(0, r.failures)
      assert.are.equal(0, #r.failure_blocks)
      assert.matches('13 successes', r.summary)
    end)

    it('parses a single failure block with its full message', function()
      local text = table.concat({
        '++++++++++++',
        '13 successes / 1 failure / 0 errors / 0 pending : 0.003975 seconds',
        '',
        'Failure -> spec/mep/org/footnote_spec.lua @ 119',
        'mep.org.footnote insert_interactive auto-numbers when the name is left blank',
        "spec/mep/org/footnote_spec.lua:136: Expected objects to be equal.",
        'Passed in:',
        "(string) '[fn:2]x'",
        'Expected:',
        "(string) 'x[fn:2]'",
        '',
        'E5113: Lua chunk: [NULL]',
      }, '\n')
      local r = tests_mod.parse_output(text)
      assert.are.equal(1, r.failures)
      assert.are.equal(1, #r.failure_blocks)
      local block = r.failure_blocks[1]
      assert.are.equal('spec/mep/org/footnote_spec.lua @ 119', block.header)
      assert.are.equal('mep.org.footnote insert_interactive auto-numbers when the name is left blank', block.body[1])
      assert.are.equal('E5113: Lua chunk: [NULL]', block.body[#block.body])
    end)

    it('splits two back-to-back failure blocks with no blank line between them', function()
      local text = table.concat({
        '5 successes / 2 failures / 0 errors / 0 pending : 0.01 seconds',
        '',
        'Failure -> spec/a_spec.lua @ 10',
        'describe a',
        'message A',
        'Failure -> spec/b_spec.lua @ 20',
        'describe b',
        'message B',
      }, '\n')
      local r = tests_mod.parse_output(text)
      assert.are.equal(2, #r.failure_blocks)
      assert.are.equal('spec/a_spec.lua @ 10', r.failure_blocks[1].header)
      assert.are.same({ 'describe a', 'message A' }, r.failure_blocks[1].body)
      assert.are.equal('spec/b_spec.lua @ 20', r.failure_blocks[2].header)
      assert.are.same({ 'describe b', 'message B' }, r.failure_blocks[2].body)
    end)

    it('treats an "Error ->" block the same as a "Failure ->" block', function()
      local text = table.concat({
        '1 success / 0 failures / 1 error / 0 pending : 0.01 seconds',
        '',
        'Error -> spec/c_spec.lua @ 5',
        'boom',
      }, '\n')
      local r = tests_mod.parse_output(text)
      assert.are.equal(1, #r.failure_blocks)
      assert.are.equal('spec/c_spec.lua @ 5', r.failure_blocks[1].header)
    end)

    it('returns zeroed counts and no summary for unrecognized output', function()
      local r = tests_mod.parse_output('nothing useful here')
      assert.is_nil(r.summary)
      assert.are.equal(0, r.successes)
      assert.are.same({}, r.failure_blocks)
    end)
  end)

  describe('run', function()
    local orig_jobstart, orig_executable
    local captured_opts

    before_each(function()
      orig_jobstart = vim.fn.jobstart
      orig_executable = vim.fn.executable
      vim.fn.executable = function()
        return 1
      end
      vim.fn.jobstart = function(_, opts)
        captured_opts = opts
        return 42
      end
    end)

    after_each(function()
      vim.fn.jobstart = orig_jobstart
      vim.fn.executable = orig_executable
    end)

    it('shows "Running..." immediately and refuses a concurrent run', function()
      tests_mod.run()
      assert.is_true(tests_mod.running)
      assert.are.equal('Running...', tests_mod.sections()[1].widgets[1].text)

      local before = captured_opts
      tests_mod.run()
      assert.are.equal(before, captured_opts) -- jobstart wasn't called again
    end)

    it('parses stdout and updates last_result on exit', function()
      tests_mod.run()
      captured_opts.on_stdout(42, { '2 successes / 0 failures / 0 errors / 0 pending : 0.01 seconds', '' })
      captured_opts.on_exit(42, 0)

      assert.is_false(tests_mod.running)
      assert.are.equal(2, tests_mod.last_result.successes)
    end)

    it('uses config.options.tests.cmd', function()
      config.setup({ tests = { cmd = { 'npm', 'test' } } })
      local cmd
      vim.fn.jobstart = function(c)
        cmd = c
        return 1
      end
      tests_mod.run()
      assert.are.same({ 'npm', 'test' }, cmd)
    end)

    it('uses the explicit tests.runner when cmd is unset', function()
      -- config.setup() can't represent "explicitly unset cmd" — a
      -- nil-valued table key is indistinguishable from an absent one in
      -- Lua, so the deep-merge would just keep the default `{'busted'}`
      -- — clear it directly on the resolved options instead.
      config.setup({ tests = { runner = 'cargo' } })
      config.options.tests.cmd = nil
      local cmd
      vim.fn.jobstart = function(c)
        cmd = c
        return 1
      end
      tests_mod.run()
      assert.are.same({ 'cargo', 'test' }, cmd)
    end)

    it('auto-detects a runner from cwd when both cmd and runner are unset', function()
      local dir = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'module x' }, dir .. '/go.mod')
      config.setup({ tests = { cwd = dir } })
      config.options.tests.cmd = nil
      local cmd
      vim.fn.jobstart = function(c)
        cmd = c
        return 1
      end
      tests_mod.run()
      assert.are.same({ 'go', 'test', '-v', './...' }, cmd)
    end)

    it('parses on_exit output through the resolved runner, not always busted', function()
      config.setup({ tests = { runner = 'cargo' } })
      config.options.tests.cmd = nil
      tests_mod.run()
      captured_opts.on_stdout(
        42,
        { 'test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out', '' }
      )
      captured_opts.on_exit(42, 1)
      assert.are.equal(1, tests_mod.last_result.successes)
      assert.are.equal(1, tests_mod.last_result.failures)
    end)
  end)

  describe('sections', function()
    it('shows just "Run tests" before any run', function()
      local widgets = tests_mod.sections()[1].widgets
      assert.are.equal(1, #widgets)
      assert.are.equal('Run tests', widgets[1].text)
    end)

    it('sources the "Run tests" icon from mep.icons (respects style)', function()
      local icons_config = require('mep.icons.config')
      local saved_icons_options = vim.deepcopy(icons_config.options)
      assert.are.equal('▶', tests_mod.sections()[1].widgets[1].icon)
      icons_config.setup({ style = 'ascii' })
      assert.are.equal('>', tests_mod.sections()[1].widgets[1].icon)
      icons_config.options = saved_icons_options
    end)

    it('shows the summary and one widget per failure after a run', function()
      tests_mod.last_result = tests_mod.parse_output(table.concat({
        '1 success / 1 failure / 0 errors / 0 pending : 0.01 seconds',
        '',
        'Failure -> spec/a_spec.lua @ 1',
        'boom',
      }, '\n'))
      local widgets = tests_mod.sections()[1].widgets
      assert.are.equal(3, #widgets) -- run button, summary, one failure
      assert.matches('1 failure', widgets[2].text)
      assert.are.equal('DiagnosticError', widgets[2].hl)
      assert.are.equal('spec/a_spec.lua @ 1', widgets[3].text)
    end)

    it('colors the summary as ok when there are no failures/errors', function()
      tests_mod.last_result = tests_mod.parse_output('3 successes / 0 failures / 0 errors / 0 pending : 0.01 seconds')
      local widgets = tests_mod.sections()[1].widgets
      assert.are.equal('DiagnosticOk', widgets[2].hl)
    end)
  end)

  describe('clicking a failure', function()
    after_each(function()
      pcall(function()
        tests_mod.sidebar():close()
      end)
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('opens a popup with the failure header and body', function()
      tests_mod.last_result = tests_mod.parse_output(table.concat({
        '0 successes / 1 failure / 0 errors / 0 pending : 0.01 seconds',
        '',
        'Failure -> spec/a_spec.lua @ 1',
        'the reason it failed',
      }, '\n'))
      tests_mod.sidebar().opts.animate = false
      tests_mod.toggle()

      vim.api.nvim_win_set_cursor(tests_mod.sidebar().win, { 4, 0 }) -- run, summary, failure
      feed('<CR>')

      local popup_win
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= tests_mod.sidebar().win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
          popup_win = win
        end
      end
      assert.is_not_nil(popup_win)
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(popup_win), 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.matches('spec/a_spec.lua @ 1', text)
      assert.matches('the reason it failed', text)
    end)
  end)
end)

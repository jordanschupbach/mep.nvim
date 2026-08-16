local leetcode = require('mep.leetcode')
local local_mod = require('mep.leetcode.local')
local runner = require('mep.leetcode.runner')
local api = require('mep.leetcode.api')
local create = require('mep.leetcode.create')
local config = require('mep.leetcode.config')

local scratch_dir = '/tmp/mep-leetcode-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.leetcode', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  it('re-exports its submodules', function()
    assert.are.equal(api, leetcode.api)
    assert.are.equal(create, leetcode.create)
    assert.are.equal(runner, leetcode.runner)
    assert.are.equal(local_mod, leetcode.local_problems)
  end)

  describe('run_tests', function()
    it('warns when the buffer has no src blocks', function()
      local path = write_file('a.org', { '* Nothing' })
      local buf = local_mod.load_buf(path)
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      leetcode.run_tests(buf)
      vim.notify = orig_notify
      assert.matches('no src blocks', notified)
    end)

    it('warns when there are no test blocks', function()
      local path = write_file('b.org', { '#+begin_src python', 'x = 1', '#+end_src' })
      local buf = local_mod.load_buf(path)
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      leetcode.run_tests(buf)
      vim.notify = orig_notify
      assert.matches('no test blocks', notified)
    end)

    it('runs every test via mep.leetcode.runner.run_all', function()
      local path = write_file('c.org', {
        '#+begin_src python',
        'x = 1',
        '#+end_src',
        '#+begin_src python',
        'print(x)',
        '#+end_src',
      })
      local buf = local_mod.load_buf(path)

      local orig_run_all = runner.run_all
      local seen_lang, seen_test_count
      runner.run_all = function(lang, solution, tests, on_each, on_all_done)
        seen_lang, seen_test_count = lang, #tests
        on_each(1, 0, { 'ok' }, {})
        on_all_done()
      end

      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified[#notified + 1] = msg
      end

      leetcode.run_tests(buf)

      vim.notify = orig_notify
      runner.run_all = orig_run_all

      assert.are.equal('python', seen_lang)
      assert.are.equal(1, seen_test_count)
      assert.matches('test 1 %-> ok', notified[1])
      assert.matches('finished', notified[2])
    end)
  end)

  describe('fetch/fetch_interactive', function()
    it('fetches, writes a local file via mep.leetcode.create, and opens it', function()
      config.setup({ problems_dir = scratch_dir })
      local orig_fetch = api.fetch_problem
      api.fetch_problem = function(slug, on_done)
        on_done(nil, { title = 'Two Sum', titleSlug = slug, codeSnippets = {} })
      end

      leetcode.fetch('two-sum')
      api.fetch_problem = orig_fetch

      assert.are.equal(1, vim.fn.filereadable(scratch_dir .. '/two-sum.org'))
      assert.matches('two%-sum%.org$', vim.api.nvim_buf_get_name(0))
    end)

    it('fetch notifies (writes nothing) on an error', function()
      config.setup({ problems_dir = scratch_dir })
      local orig_fetch = api.fetch_problem
      api.fetch_problem = function(_, on_done)
        on_done('boom', nil)
      end
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end

      leetcode.fetch('bad-slug')

      vim.notify = orig_notify
      api.fetch_problem = orig_fetch
      assert.are.equal('boom', notified)
      assert.are.equal(0, vim.fn.filereadable(scratch_dir .. '/bad-slug.org'))
    end)

    it('fetch_interactive prompts then fetches', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('two-sum')
      end
      local orig_fetch = api.fetch_problem
      local seen_slug
      api.fetch_problem = function(slug)
        seen_slug = slug
      end

      leetcode.fetch_interactive()

      vim.ui.input = orig_input
      api.fetch_problem = orig_fetch
      assert.are.equal('two-sum', seen_slug)
    end)

    it('fetch_interactive does nothing when the prompt is cancelled', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      local orig_fetch = api.fetch_problem
      local called = false
      api.fetch_problem = function()
        called = true
      end

      leetcode.fetch_interactive()

      vim.ui.input = orig_input
      api.fetch_problem = orig_fetch
      assert.is_false(called)
    end)
  end)

  describe('submit', function()
    it('warns when the file has no LEETCODE_SLUG property', function()
      local path = write_file('d.org', { '#+begin_src python', 'x = 1', '#+end_src' })
      local buf = local_mod.load_buf(path)
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      leetcode.submit(buf)
      vim.notify = orig_notify
      assert.matches('LEETCODE_SLUG', notified)
    end)

    it('warns when the buffer has no Solution block', function()
      local path = write_file('e.org', { '#+PROPERTY: LEETCODE_SLUG two-sum' })
      local buf = local_mod.load_buf(path)
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      leetcode.submit(buf)
      vim.notify = orig_notify
      assert.matches('no Solution block', notified)
    end)

    it('warns when the solution language has no known LeetCode slug', function()
      local path = write_file('f.org', {
        '#+PROPERTY: LEETCODE_SLUG two-sum',
        '#+begin_src lua',
        'x = 1',
        '#+end_src',
      })
      local buf = local_mod.load_buf(path)
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      leetcode.submit(buf)
      vim.notify = orig_notify
      assert.matches('no LeetCode language slug', notified)
    end)

    it('submits directly using a stored LEETCODE_QUESTION_ID, without re-fetching', function()
      local path = write_file('g.org', {
        '#+PROPERTY: LEETCODE_SLUG two-sum',
        '#+PROPERTY: LEETCODE_QUESTION_ID 1',
        '#+begin_src python',
        'def f(): pass',
        '#+end_src',
      })
      local buf = local_mod.load_buf(path)

      local orig_fetch = api.fetch_problem
      local fetch_called = false
      api.fetch_problem = function()
        fetch_called = true
      end
      local orig_submit = api.submit
      local seen
      api.submit = function(slug, question_id, lang_slug, code, on_done)
        seen = { slug = slug, question_id = question_id, lang_slug = lang_slug, code = code }
        on_done(nil, { status_msg = 'Accepted', total_correct = 1, total_testcases = 1 })
      end

      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end

      leetcode.submit(buf)

      vim.notify = orig_notify
      api.fetch_problem = orig_fetch
      api.submit = orig_submit

      assert.is_false(fetch_called)
      assert.are.equal('two-sum', seen.slug)
      assert.are.equal('1', seen.question_id)
      assert.are.equal('python3', seen.lang_slug)
      assert.matches('def f%(%): pass', seen.code)
      assert.matches('Accepted %(1/1%)', notified)
    end)

    it('fetches the question id first when the file has none stored', function()
      local path = write_file('h.org', {
        '#+PROPERTY: LEETCODE_SLUG two-sum',
        '#+begin_src python',
        'def f(): pass',
        '#+end_src',
      })
      local buf = local_mod.load_buf(path)

      local orig_fetch = api.fetch_problem
      api.fetch_problem = function(slug, on_done)
        on_done(nil, { questionId = '42' })
      end
      local orig_submit = api.submit
      local seen_question_id
      api.submit = function(_, question_id, _, _, on_done)
        seen_question_id = question_id
        on_done(nil, { status_msg = 'Accepted', total_correct = 1, total_testcases = 1 })
      end

      leetcode.submit(buf)

      api.fetch_problem = orig_fetch
      api.submit = orig_submit
      assert.are.equal('42', seen_question_id)
    end)
  end)

  describe('setup', function()
    it('binds the configured picker keymap', function()
      local keymaps = { picker = { '<localleader>lcx' } }
      leetcode.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>lcx', 'n', false, true)))
      del_all(keymaps.picker)
    end)

    it('returns the resolved options', function()
      local options = leetcode.setup({ default_language = 'go', keymaps = { picker = {} } })
      assert.are.equal('go', options.default_language)
    end)
  end)
end)

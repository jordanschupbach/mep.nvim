-- Mocks vim.fn.jobstart (the same core.job.spawn contract every other
-- job-backed spec in this suite mocks — see spec/README.md) rather than
-- spawning real curl processes, and vim.defer_fn (made synchronous) so
-- mep.leetcode.api.submit's poll loop runs deterministically without a
-- real timer/vim.wait.
local api = require('mep.leetcode.api')
local config = require('mep.leetcode.config')

describe('mep.leetcode.api', function()
  local orig_jobstart, orig_defer_fn
  local saved_options
  local captured

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_jobstart = vim.fn.jobstart
    orig_defer_fn = vim.defer_fn
    vim.defer_fn = function(fn)
      fn()
    end
    vim.fn.jobstart = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      return 1
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.defer_fn = orig_defer_fn
    config.options = saved_options
  end)

  local function set_env(name, value)
    vim.env[name] = value
  end

  describe('credentials', function()
    it('returns nil plus a message when either env var is unset', function()
      set_env(config.options.session_cookie_env, nil)
      set_env(config.options.csrf_token_env, nil)
      local creds, err = api.credentials()
      assert.is_nil(creds)
      assert.matches('missing credentials', err)
    end)

    it('returns both values when set', function()
      set_env(config.options.session_cookie_env, 'sess123')
      set_env(config.options.csrf_token_env, 'csrf456')
      local creds = api.credentials()
      assert.are.equal('sess123', creds.session)
      assert.are.equal('csrf456', creds.csrf)
      set_env(config.options.session_cookie_env, nil)
      set_env(config.options.csrf_token_env, nil)
    end)
  end)

  describe('fetch_problem', function()
    before_each(function()
      set_env(config.options.session_cookie_env, 'sess')
      set_env(config.options.csrf_token_env, 'csrf')
    end)

    after_each(function()
      set_env(config.options.session_cookie_env, nil)
      set_env(config.options.csrf_token_env, nil)
    end)

    it('calls back with an error, no request sent, when credentials are missing', function()
      set_env(config.options.session_cookie_env, nil)
      local err
      api.fetch_problem('two-sum', function(e)
        err = e
      end)
      assert.matches('missing credentials', err)
      assert.is_nil(captured)
    end)

    it('POSTs to /graphql with cookie and csrf headers', function()
      api.fetch_problem('two-sum', function() end)
      assert.are.equal('curl', captured.cmd[1])
      local joined = table.concat(captured.cmd, ' ')
      assert.matches('https://leetcode%.com/graphql', joined)
      assert.matches('Cookie: LEETCODE_SESSION=sess; csrftoken=csrf', joined)
      assert.matches('x%-csrftoken: csrf', joined)
    end)

    it('sends titleSlug as a GraphQL variable in the request body', function()
      api.fetch_problem('two-sum', function() end)
      local idx
      for i, arg in ipairs(captured.cmd) do
        if arg == '--data-binary' then
          idx = i
        end
      end
      local body_path = captured.cmd[idx + 1]:sub(2)
      local body = vim.json.decode(vim.fn.readfile(body_path)[1])
      assert.are.equal('two-sum', body.variables.titleSlug)
      vim.fn.delete(body_path)
    end)

    it('calls back with the question on a successful response', function()
      local got_err, got_question
      api.fetch_problem('two-sum', function(err, question)
        got_err, got_question = err, question
      end)
      local response = vim.json.encode({ data = { question = { title = 'Two Sum', titleSlug = 'two-sum' } } })
      captured.opts.on_stdout(1, { response, '' })
      captured.opts.on_exit(1, 0)
      assert.is_nil(got_err)
      assert.are.equal('Two Sum', got_question.title)
    end)

    it('calls back with an error for a nonzero exit', function()
      local got_err
      api.fetch_problem('two-sum', function(err)
        got_err = err
      end)
      captured.opts.on_stderr(1, { 'connection refused', '' })
      captured.opts.on_exit(1, 7)
      assert.matches('connection refused', got_err)
    end)

    it('calls back with an error when the response has no question (e.g. bad slug)', function()
      local got_err
      api.fetch_problem('not-a-real-slug', function(err)
        got_err = err
      end)
      captured.opts.on_stdout(1, { vim.json.encode({ data = {} }), '' })
      captured.opts.on_exit(1, 0)
      assert.matches('no such problem', got_err)
    end)
  end)

  describe('submit', function()
    before_each(function()
      set_env(config.options.session_cookie_env, 'sess')
      set_env(config.options.csrf_token_env, 'csrf')
    end)

    after_each(function()
      set_env(config.options.session_cookie_env, nil)
      set_env(config.options.csrf_token_env, nil)
    end)

    it('POSTs lang/question_id/typed_code, with a Referer header', function()
      api.submit('two-sum', '1', 'python3', 'def f(): pass', function() end)
      local joined = table.concat(captured.cmd, ' ')
      assert.matches('leetcode%.com/problems/two%-sum/submit/', joined)
      assert.matches('Referer: https://leetcode%.com/problems/two%-sum/', joined)

      local idx
      for i, arg in ipairs(captured.cmd) do
        if arg == '--data-binary' then
          idx = i
        end
      end
      local body_path = captured.cmd[idx + 1]:sub(2)
      local body = vim.json.decode(vim.fn.readfile(body_path)[1])
      assert.are.equal('python3', body.lang)
      assert.are.equal('1', body.question_id)
      assert.are.equal('def f(): pass', body.typed_code)
      vim.fn.delete(body_path)
    end)

    it('polls the check endpoint until state is SUCCESS, then calls back with the result', function()
      local got_err, got_result
      api.submit('two-sum', '1', 'python3', 'def f(): pass', function(err, result)
        got_err, got_result = err, result
      end)
      -- Submit response.
      captured.opts.on_stdout(1, { vim.json.encode({ submission_id = 999 }), '' })
      captured.opts.on_exit(1, 0)

      -- First poll: still pending.
      assert.matches('submissions/detail/999/check/', table.concat(captured.cmd, ' '))
      captured.opts.on_stdout(1, { vim.json.encode({ state = 'PENDING' }), '' })
      captured.opts.on_exit(1, 0)

      -- Second poll: finished.
      captured.opts.on_stdout(1, { vim.json.encode({ state = 'SUCCESS', status_msg = 'Accepted', total_correct = 2, total_testcases = 2 }), '' })
      captured.opts.on_exit(1, 0)

      assert.is_nil(got_err)
      assert.are.equal('Accepted', got_result.status_msg)
      assert.are.equal(2, got_result.total_correct)
    end)

    it('gives up with a timeout error after poll_max_attempts', function()
      api.poll_max_attempts = 2
      local got_err
      api.submit('two-sum', '1', 'python3', 'code', function(err)
        got_err = err
      end)
      captured.opts.on_stdout(1, { vim.json.encode({ submission_id = 1 }), '' })
      captured.opts.on_exit(1, 0)

      for _ = 1, 2 do
        captured.opts.on_stdout(1, { vim.json.encode({ state = 'PENDING' }), '' })
        captured.opts.on_exit(1, 0)
      end

      assert.matches('timed out', got_err)
      api.poll_max_attempts = 20
    end)

    it('calls back with an error when the submit response has no submission_id', function()
      local got_err
      api.submit('two-sum', '1', 'python3', 'code', function(err)
        got_err = err
      end)
      captured.opts.on_stdout(1, { vim.json.encode({}), '' })
      captured.opts.on_exit(1, 0)
      assert.matches('did not return a submission id', got_err)
    end)

    it('calls back with an error, no request sent, when credentials are missing', function()
      set_env(config.options.session_cookie_env, nil)
      local err
      api.submit('two-sum', '1', 'python3', 'code', function(e)
        err = e
      end)
      assert.matches('missing credentials', err)
    end)
  end)
end)

-- mep.repl ultimately calls vim.fn.jobstart(cmd, { term = true }) to
-- start a REPL — mocked here (plus vim.fn.jobwait/vim.fn.chansend) the
-- same way every other job-backed spec in this suite mocks jobstart, so
-- no real subprocess/terminal job ever actually spawns (see
-- spec/README.md).
local repl = require('mep.repl')
local config = require('mep.repl.config')
local state = require('mep.repl.state')

local function del_all(lhs_list, mode)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, mode or 'n', lhs)
  end
end

describe('mep.repl', function()
  local orig_jobstart, orig_jobwait, orig_chansend
  local saved_options
  local next_job_id
  local sent

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_jobstart = vim.fn.jobstart
    orig_jobwait = vim.fn.jobwait
    orig_chansend = vim.fn.chansend
    next_job_id = 1
    sent = {}
    vim.fn.jobstart = function()
      local id = next_job_id
      next_job_id = next_job_id + 1
      return id
    end
    -- Every started job is "still running" by default; tests that need
    -- a dead one override this per-test.
    vim.fn.jobwait = function(ids)
      return { -1 }
    end
    vim.fn.chansend = function(id, text)
      sent[#sent + 1] = { id = id, text = text }
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobwait = orig_jobwait
    vim.fn.chansend = orig_chansend
    config.options = saved_options
    repl._reset()
    -- Each test's own REPL split(s) stay open otherwise, eventually
    -- running the shared test-session editor out of room to split
    -- further (E36) — collapse back down to one window every time.
    pcall(vim.cmd, 'only')
  end)

  local function make_buf(filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype
    return bufnr
  end

  describe('session_key', function()
    it('uses filetype by default', function()
      local bufnr = make_buf('python')
      assert.are.equal('python', repl.session_key(bufnr))
    end)

    it('uses the bufnr when scope = "buffer"', function()
      config.setup({ scope = 'buffer' })
      local bufnr = make_buf('python')
      assert.are.equal(bufnr, repl.session_key(bufnr))
    end)
  end)

  describe('ensure_session', function()
    it('starts a new REPL for a curated filetype', function()
      local bufnr = make_buf('python')
      local session = repl.ensure_session(bufnr)
      assert.is_not_nil(session)
      assert.is_number(session.job_id)
      assert.is_true(vim.api.nvim_buf_is_valid(session.bufnr))
      assert.are.equal(state.get('python'), session)
    end)

    it('reuses an already-alive session instead of starting a second one', function()
      local bufnr = make_buf('python')
      local first = repl.ensure_session(bufnr)
      local second = repl.ensure_session(bufnr)
      assert.are.equal(first, second)
    end)

    it('starts a fresh session when the previous one has died', function()
      local bufnr = make_buf('python')
      local first = repl.ensure_session(bufnr)
      vim.fn.jobwait = function()
        return { 1 } -- exited with code 1, not -1 (still running)
      end
      local second = repl.ensure_session(bufnr)
      assert.are_not.equal(first.job_id, second.job_id)
    end)

    it('returns nil and notifies for a filetype with no REPL command', function()
      local bufnr = make_buf('brainfuck')
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      local session = repl.ensure_session(bufnr)
      vim.notify = orig_notify
      assert.is_nil(session)
      assert.matches('no REPL command', notified)
    end)

    it('returns focus to the source window after starting a fresh session', function()
      local bufnr = make_buf('python')
      local win = vim.api.nvim_get_current_win()
      repl.ensure_session(bufnr)
      assert.are.equal(win, vim.api.nvim_get_current_win())
    end)

    it('keeps separate sessions per filetype', function()
      local py_buf = make_buf('python')
      local lua_buf = make_buf('lua')
      local py_session = repl.ensure_session(py_buf)
      local lua_session = repl.ensure_session(lua_buf)
      assert.are_not.equal(py_session.bufnr, lua_session.bufnr)
    end)

    it('shares one session across buffers of the same filetype', function()
      local buf1 = make_buf('python')
      local buf2 = make_buf('python')
      assert.are.equal(repl.ensure_session(buf1), repl.ensure_session(buf2))
    end)

    it('keeps separate sessions per buffer when scope = "buffer"', function()
      config.setup({ scope = 'buffer' })
      local buf1 = make_buf('python')
      local buf2 = make_buf('python')
      assert.are_not.equal(repl.ensure_session(buf1).bufnr, repl.ensure_session(buf2).bufnr)
    end)
  end)

  describe('send_line/send_selection/send_buffer', function()
    it('send_line sends the line at the cursor', function()
      local bufnr = make_buf('python')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
      repl.send_line(bufnr, 2)
      assert.are.equal(1, #sent)
      assert.are.equal('two\n', sent[1].text)
    end)

    it('send_selection sends an inclusive line range', function()
      local bufnr = make_buf('python')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c', 'd' })
      repl.send_selection(bufnr, 2, 3)
      assert.are.equal('b\nc\n', sent[1].text)
    end)

    it('send_selection swaps a reversed range', function()
      local bufnr = make_buf('python')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c' })
      repl.send_selection(bufnr, 3, 1)
      assert.are.equal('a\nb\nc\n', sent[1].text)
    end)

    it('send_buffer sends every line', function()
      local bufnr = make_buf('python')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x = 1', 'print(x)' })
      repl.send_buffer(bufnr)
      assert.are.equal('x = 1\nprint(x)\n', sent[1].text)
    end)

    it('sends to the same job_id on repeated calls (session reuse)', function()
      local bufnr = make_buf('python')
      repl.send_line(bufnr, 1)
      repl.send_line(bufnr, 1)
      assert.are.equal(sent[1].id, sent[2].id)
    end)
  end)

  describe('jump_to_repl', function()
    it('focuses the REPL window', function()
      local bufnr = make_buf('python')
      repl.jump_to_repl(bufnr)
      local session = state.get('python')
      assert.are.equal(session.bufnr, vim.api.nvim_get_current_buf())
    end)

    it('reopens a split for an alive session whose window was closed', function()
      local bufnr = make_buf('python')
      repl.jump_to_repl(bufnr)
      local session = state.get('python')
      local old_win = session.win
      vim.api.nvim_win_close(old_win, true)

      repl.jump_to_repl(bufnr)
      local new_session = state.get('python')
      assert.are.equal(session.bufnr, new_session.bufnr) -- same job, not a new one
      assert.is_true(vim.api.nvim_win_is_valid(new_session.win))
      assert.are_not.equal(old_win, new_session.win)
    end)
  end)

  describe('jump_back', function()
    it('jumps to the source window from inside the REPL buffer', function()
      local bufnr = make_buf('python')
      local code_win = vim.api.nvim_get_current_win()
      repl.jump_to_repl(bufnr) -- now focused in the REPL window
      assert.are_not.equal(code_win, vim.api.nvim_get_current_win())

      repl.jump_back()
      assert.are.equal(code_win, vim.api.nvim_get_current_win())
    end)

    it('is a no-op from a buffer that is not a tracked REPL session', function()
      local other = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(other)
      assert.has_no.errors(function()
        repl.jump_back()
      end)
    end)
  end)

  describe('setup', function()
    it('binds send_line/send_buffer/jump_to_repl in normal mode', function()
      local keymaps = {
        send_line = { '<localleader>rl' },
        send_selection = { '<localleader>rs' },
        send_buffer = { '<localleader>rb' },
        jump_to_repl = { '<localleader>rj' },
        jump_back = { '<localleader>rc' },
      }
      repl.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>rl', 'n', false, true)))
      assert.is_not_nil(next(vim.fn.maparg('<localleader>rb', 'n', false, true)))
      assert.is_not_nil(next(vim.fn.maparg('<localleader>rj', 'n', false, true)))
      del_all(keymaps.send_line)
      del_all(keymaps.send_buffer)
      del_all(keymaps.jump_to_repl)
      del_all(keymaps.send_selection, 'x')
    end)

    it('binds send_selection in visual mode', function()
      local lhs = '<localleader>rv'
      repl.setup({
        keymaps = { send_selection = { lhs }, send_line = {}, send_buffer = {}, jump_to_repl = {}, jump_back = {} },
      })
      assert.is_not_nil(next(vim.fn.maparg(lhs, 'x', false, true)))
      del_all({ lhs }, 'x')
    end)

    it('binds jump_back inside each REPL terminal buffer it creates, not globally', function()
      local keymaps = { jump_back = { '<localleader>rk' } }
      repl.setup({
        keymaps = { jump_back = keymaps.jump_back, send_line = {}, send_selection = {}, send_buffer = {}, jump_to_repl = {} },
      })

      local bufnr = make_buf('python')
      repl.ensure_session(bufnr)
      local session = state.get('python')

      local map = vim.api.nvim_buf_call(session.bufnr, function()
        return vim.fn.maparg('<localleader>rk', 'n', false, true)
      end)
      assert.is_not_nil(next(map))

      local global_map = vim.fn.maparg('<localleader>rk', 'n', false, true)
      assert.is_nil(next(global_map))
    end)

    it('returns the resolved options', function()
      local options = repl.setup({ scope = 'buffer', keymaps = { send_line = {}, send_selection = {}, send_buffer = {}, jump_to_repl = {}, jump_back = {} } })
      assert.are.equal('buffer', options.scope)
    end)
  end)
end)

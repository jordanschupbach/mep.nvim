-- mep.ai.job.start is a module-level dependency, stubbed the way
-- spec/README.md describes (save the original, replace, restore) rather
-- than mocking vim.fn.jobstart transitively — mep.ai.job already has its
-- own dedicated spec for that layer.
local ai = require('mep.ai')
local config = require('mep.ai.config')
local job_mod = require('mep.ai.job')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.ai', function()
  local orig_start, orig_inputsecret
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_start = job_mod.start
    orig_inputsecret = vim.fn.inputsecret
  end)

  after_each(function()
    -- `active_job`/`session_keys` are module-local state in mep.ai.ai; a
    -- test that calls send() without ever invoking its mocked job's
    -- on_done leaves `active_job` set (which would make every later
    -- test's own send() hit the "already streaming" refusal instead of
    -- actually starting), and any test that resolves/prompts for a key
    -- leaves it cached in `session_keys` (which would make a later
    -- test's own "is this actually unset" premise silently false) — same
    -- "clean up what setup() left behind" reasoning spec/README.md gives
    -- for autocmds/buffers, just for this module's own in-memory state.
    ai._reset()

    config.options = saved_options
    job_mod.start = orig_start
    vim.fn.inputsecret = orig_inputsecret
  end)

  describe('send', function()
    it('errors when no provider is configured at all', function()
      config.setup({})
      -- a literal `nil` in a setup({ provider = nil }) table constructor
      -- doesn't actually create a `provider` key at all (Lua can't store
      -- nil in a table that way), so it would just leave the shipped
      -- default (a fallback list) in place instead of testing the "truly
      -- unset" case at all — set it directly here instead.
      config.options.provider = nil
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        notified = { msg = msg, level = level }
      end
      ai.send()
      vim.notify = orig_notify
      assert.matches('no provider configured', notified.msg)
      assert.are.equal(vim.log.levels.ERROR, notified.level)
    end)

    it('errors on an unknown provider name', function()
      config.setup({ provider = 'nope' })
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.send()
      vim.notify = orig_notify
      assert.matches('unknown provider', notified)
    end)

    it('errors when the configured provider has no model set', function()
      config.setup({ provider = 'openai' })
      -- same nil-in-table-constructor non-issue as the "no provider at
      -- all" test above: `providers = { openai = { model = nil } }`
      -- wouldn't actually clear the shipped default model, so it's
      -- cleared directly here instead.
      config.options.providers.openai.model = nil
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.send()
      vim.notify = orig_notify
      assert.matches('no `model` configured', notified)
    end)

    it('sends the whole buffer as a single user message', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'line one', 'line two' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 8 })

      local captured_messages
      job_mod.start = function(provider, messages, on_delta, on_done)
        captured_messages = messages
        return { kill = function() end }
      end

      ai.send()
      assert.are.same({ { role = 'user', content = 'line one\nline two' } }, captured_messages)
    end)

    it('prepends a system message when system_prompt is set', function()
      config.setup({
        provider = 'ollama',
        providers = { ollama = { model = 'llama3.2' } },
        system_prompt = 'be terse',
      })
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)

      local captured_messages
      job_mod.start = function(provider, messages)
        captured_messages = messages
        return { kill = function() end }
      end

      ai.send()
      assert.are.same({
        { role = 'system', content = 'be terse' },
        { role = 'user', content = 'hi' },
      }, captured_messages)
    end)

    it('reads the API key from the provider\'s own env var when set', function()
      config.setup({ provider = 'openai', providers = { openai = { model = 'gpt-x' } } })
      local orig_getenv = os.getenv
      os.getenv = function(name)
        if name == 'OPENAI_API_KEY' then
          return 'sk-from-env'
        end
        return orig_getenv(name)
      end

      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end

      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      os.getenv = orig_getenv

      assert.are.equal('sk-from-env', captured_provider.api_key)
    end)

    it('prompts (and caches) the API key when neither a literal nor an env var one is set', function()
      config.setup({ provider = 'openai', providers = { openai = { model = 'gpt-x', api_key_env = 'MEP_AI_TEST_UNSET_VAR' } } })
      vim.fn.inputsecret = function()
        return 'sk-typed'
      end

      local calls = 0
      local captured_provider
      job_mod.start = function(provider)
        calls = calls + 1
        captured_provider = provider
        return { kill = function() end }
      end

      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      assert.are.equal('sk-typed', captured_provider.api_key)
      ai.cancel() -- clear active_job so the second send() below can start

      -- second send() must not prompt again -- cached for the session
      vim.fn.inputsecret = function()
        error('should not be called again')
      end
      ai.send()
      assert.are.equal(2, calls)
    end)

    it('does not prompt for a provider with no api_key_env at all (e.g. a local Ollama)', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      vim.fn.inputsecret = function()
        error('should never be called for a keyless provider')
      end
      job_mod.start = function()
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      assert.has_no.errors(function()
        ai.send()
      end)
    end)

    it('refuses to start a second request while one is already streaming', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local starts = 0
      job_mod.start = function()
        starts = starts + 1
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)

      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.send()
      ai.send()
      vim.notify = orig_notify

      assert.are.equal(1, starts)
      assert.matches('already streaming', notified)
      ai.cancel()
    end)

    it('inserts a streamed delta at the cursor and advances it for a single-line chunk', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'ab' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 1 }) -- between 'a' and 'b'

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta, on_done)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send()

      on_delta_fn('XY')
      assert.are.same({ 'aXYb' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.same({ 1, 3 }, vim.api.nvim_win_get_cursor(0)) -- cursor moved past the inserted text
    end)

    it('inserts a multi-line delta and advances the cursor to the new row', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'end' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send()

      on_delta_fn('one\ntwo')
      assert.are.same({ 'one', 'twoend' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.same({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
    end)

    it('keeps landing correctly even when other lines are inserted above the streaming position mid-stream', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'target line' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- right before "line"

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send()

      on_delta_fn('X')
      -- something else (the user, or another plugin) edits the buffer
      -- *above* the streaming position -- a plain frozen {row, col}
      -- would now be pointing at the wrong row entirely
      vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted before', 'more inserted lines' })

      on_delta_fn('Y')
      assert.are.same(
        { 'inserted before', 'more inserted lines', 'targetXY line' },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
    end)

    it('stops auto-following the cursor once the user moves it away, but keeps inserting correctly', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'ab', 'cd' })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 1 }) -- between 'a' and 'b'

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send()

      on_delta_fn('1')
      assert.are.same({ 1, 2 }, vim.api.nvim_win_get_cursor(0)) -- auto-followed so far

      -- the user moves the cursor away on their own, to a totally
      -- different line
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      on_delta_fn('2')
      -- text still lands at the tracked (extmark) position, not wherever
      -- the cursor now is
      assert.are.same({ 'a12b', 'cd' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      -- but the real cursor is left alone, exactly where the user put it
      assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
    end)

    it('lands correctly in a background buffer while a different buffer is current', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local target_buf = make_buf({ 'ab' })
      local target_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_buf(target_buf)
      vim.api.nvim_win_set_cursor(0, { 1, 1 })

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send()

      -- switch to an entirely different buffer, as if the user moved on
      -- to do something else
      local other_buf = make_buf({ 'unrelated' })
      vim.api.nvim_set_current_buf(other_buf)

      on_delta_fn('X')
      assert.are.same({ 'aXb' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
      assert.are.same({ 'unrelated' }, vim.api.nvim_buf_get_lines(other_buf, 0, -1, false))
      assert.are.equal(other_buf, vim.api.nvim_win_get_buf(target_win)) -- still on the other buffer, undisturbed
    end)
  end)

  describe('send_selection', function()
    it('clears the selected lines to one placeholder, then streams the replacement in starting there', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'before', 'old line one', 'old line two', 'after' })
      vim.api.nvim_set_current_buf(buf)

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end
      ai.send_selection(2, 3)

      -- the two selected lines are gone, replaced by one empty
      -- placeholder line, before the model has said anything at all
      assert.are.same({ 'before', '', 'after' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

      on_delta_fn('new line one\nnew line two')
      assert.are.same({ 'before', 'new line one', 'new line two', 'after' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('sends the agent system prompt, not the plain system_prompt', function()
      config.setup({
        provider = 'ollama',
        providers = { ollama = { model = 'llama3.2' } },
        system_prompt = 'be terse', -- must NOT leak into send_selection's own messages
      })
      local buf = make_buf({ 'some code' })
      vim.api.nvim_set_current_buf(buf)

      local captured_messages
      job_mod.start = function(provider, messages)
        captured_messages = messages
        return { kill = function() end }
      end
      ai.send_selection(1, 1)

      assert.are.equal('system', captured_messages[1].role)
      assert.are.equal(config.options.agent_system_prompt, captured_messages[1].content)
    end)

    it('includes the block text and filetype, with no explicit instructions, for gl-style calls', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'def add(a, b):', '    return a - b  # TODO: fix' })
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = 'python'

      local captured_messages
      job_mod.start = function(provider, messages)
        captured_messages = messages
        return { kill = function() end }
      end
      ai.send_selection(1, 2)

      local user_content = captured_messages[2].content
      assert.are.equal('user', captured_messages[2].role)
      assert.matches('Filetype: python', user_content, 1, true)
      assert.matches('def add%(a, b%):', user_content)
      assert.matches('return a %- b  # TODO: fix', user_content)
      assert.is_nil(user_content:match('Instructions:'))
    end)

    it('includes explicit instructions alongside the block, when given (e.g. :MepAiSendSelectionPrompt)', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'x = 1' })
      vim.api.nvim_set_current_buf(buf)

      local captured_messages
      job_mod.start = function(provider, messages)
        captured_messages = messages
        return { kill = function() end }
      end
      ai.send_selection(1, 1, { instructions = 'rename x to total' })

      assert.matches('Instructions: rename x to total', captured_messages[2].content, 1, true)
    end)

    it('normalizes a partial-line (charwise) selection to the whole lines it touches', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'aaa bbb ccc' })
      vim.api.nvim_set_current_buf(buf)

      job_mod.start = function()
        return { kill = function() end }
      end
      ai.send_selection(1, 1) -- whole-line granularity regardless of column
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('swaps start_line/end_line when given in the wrong order', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'a', 'b', 'c' })
      vim.api.nvim_set_current_buf(buf)

      job_mod.start = function()
        return { kill = function() end }
      end
      ai.send_selection(3, 1)
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('refuses (with a notification) while a request is already streaming', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local buf = make_buf({ 'a', 'b' })
      vim.api.nvim_set_current_buf(buf)
      local starts = 0
      job_mod.start = function()
        starts = starts + 1
        return { kill = function() end }
      end
      ai.send()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.send_selection(1, 2)
      vim.notify = orig_notify

      assert.are.equal(1, starts)
      assert.matches('already streaming', notified)
    end)
  end)

  describe('setup keymaps', function()
    -- mep.ai's own keymaps are deliberately global, not buffer-local
    -- (see mep.ai.ai's own M.setup comment) -- vim.keymap.set(...) here
    -- really does register on the shared test Neovim instance, for
    -- every one of the four keymap groups `M.setup` binds (not just the
    -- one this test presses), so all of them have to come back off
    -- again afterward, or they'd leak into every other spec file's own
    -- key presses for the rest of this busted run. `config.defaults.
    -- keymaps` is a plain array-shaped table per lhs group -- passing an
    -- override `keymaps` table to `setup()` here would deep-merge by
    -- index rather than replacing a whole group, so this deliberately
    -- doesn't try to silence the other three groups via `keymaps = {...}`
    -- and instead just tears down whatever the real defaults bound.
    after_each(function()
      pcall(vim.keymap.del, 'n', 'gl') -- keymaps.send
      pcall(vim.keymap.del, 'x', 'gl') -- keymaps.replace_selection
      pcall(vim.keymap.del, 'x', 'gk') -- keymaps.agent_prompt
      pcall(vim.keymap.del, 'n', '<leader>ax') -- keymaps.cancel
    end)

    it('binds visual-mode replace_selection to M.send_selection, replacing the selection in place', function()
      local options = ai.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })

      local buf = make_buf({ 'before', 'old one', 'old two', 'after' })
      vim.api.nvim_set_current_buf(buf)

      local on_delta_fn
      job_mod.start = function(provider, messages, on_delta)
        on_delta_fn = on_delta
        return { kill = function() end }
      end

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.cmd('normal! Vj') -- visually select lines 2-3
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('gl', true, false, true), 'x', false)

      -- left Visual mode, cleared the two selected lines to one
      -- placeholder, same as calling M.send_selection(2, 3) directly
      assert.are.equal('n', vim.fn.mode())
      assert.are.same({ 'before', '', 'after' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

      on_delta_fn('new one\nnew two')
      assert.are.same({ 'before', 'new one', 'new two', 'after' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.same({ 'gl' }, options.keymaps.replace_selection)
    end)
  end)

  describe('send with a fallback provider list', function()
    it('uses the default fallback list ({openai, anthropic, ollama}) when provider is untouched', function()
      config.setup({})
      local orig_getenv = os.getenv
      os.getenv = function(name)
        return nil -- neither cloud key is set
      end
      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      os.getenv = orig_getenv

      -- lands on ollama, the chain's always-available last resort
      assert.are.equal('ollama', captured_provider.name)
    end)

    it('picks the first entry whose env var is actually set, in priority order', function()
      config.setup({})
      local orig_getenv = os.getenv
      os.getenv = function(name)
        if name == 'ANTHROPIC_API_KEY' then
          return 'sk-ant-from-env'
        end
        return nil
      end
      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      os.getenv = orig_getenv

      assert.are.equal('anthropic', captured_provider.name)
      assert.are.equal('sk-ant-from-env', captured_provider.api_key)
    end)

    it('prefers an earlier entry over a later one when both are set', function()
      config.setup({})
      local orig_getenv = os.getenv
      os.getenv = function(name)
        if name == 'OPENAI_API_KEY' then
          return 'sk-openai'
        elseif name == 'ANTHROPIC_API_KEY' then
          return 'sk-ant'
        end
        return nil
      end
      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      os.getenv = orig_getenv

      assert.are.equal('openai', captured_provider.name)
    end)

    it('never prompts interactively while walking the fallback list', function()
      config.setup({})
      local orig_getenv = os.getenv
      os.getenv = function()
        return nil
      end
      vim.fn.inputsecret = function()
        error('a fallback list must never prompt')
      end
      job_mod.start = function()
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      assert.has_no.errors(function()
        ai.send()
      end)
      os.getenv = orig_getenv
    end)

    it('errors clearly (without prompting) when every entry in an explicit list is unusable', function()
      config.setup({ provider = { 'openai', 'anthropic' } }) -- no keyless fallback in this list
      local orig_getenv = os.getenv
      os.getenv = function()
        return nil
      end
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.send()
      vim.notify = orig_notify
      os.getenv = orig_getenv

      assert.matches('none of the configured providers are ready', notified)
    end)

    it('skips an unknown or misconfigured name in the list rather than failing the whole chain', function()
      config.setup({ provider = { 'not-a-real-provider', 'ollama' }, providers = { ollama = { model = 'llama3.2' } } })
      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      assert.are.equal('ollama', captured_provider.name)
    end)
  end)

  describe('cancel', function()
    it('kills the active job and clears it', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      local killed = false
      job_mod.start = function()
        return { kill = function() killed = true end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()
      ai.cancel()
      assert.is_true(killed)
    end)

    it('is a no-op (with a notification) when nothing is streaming', function()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.cancel()
      vim.notify = orig_notify
      assert.matches('nothing streaming', notified)
    end)
  end)

  describe('set_key', function()
    it('prompts for and caches a key that a later send() then uses', function()
      config.setup({ provider = 'openai', providers = { openai = { model = 'gpt-x', api_key_env = 'MEP_AI_TEST_UNSET_VAR2' } } })
      vim.fn.inputsecret = function()
        return 'sk-preset'
      end
      ai.set_key('openai')

      vim.fn.inputsecret = function()
        error('should not prompt again after set_key')
      end
      local captured_provider
      job_mod.start = function(provider)
        captured_provider = provider
        return { kill = function() end }
      end
      local buf = make_buf({ 'hi' })
      vim.api.nvim_set_current_buf(buf)
      ai.send()

      assert.are.equal('sk-preset', captured_provider.api_key)
    end)

    it('is a no-op for a provider that needs no key at all', function()
      config.setup({ provider = 'ollama', providers = { ollama = { model = 'llama3.2' } } })
      vim.fn.inputsecret = function()
        error('should never be called')
      end
      assert.has_no.errors(function()
        ai.set_key('ollama')
      end)
    end)

    it('requires an explicit name (errors, no prompt) when provider is a fallback list', function()
      config.setup({}) -- default provider is the {openai, anthropic, ollama} list
      vim.fn.inputsecret = function()
        error('ambiguous which provider to prompt for — must not prompt')
      end
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      ai.set_key() -- no explicit name given
      vim.notify = orig_notify
      assert.matches('fallback list', notified)
    end)
  end)
end)

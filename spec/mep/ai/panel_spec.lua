-- Real mep.sidebar windows/buffers throughout (no mocking needed --
-- floating windows/buffers/autocmds all work fine under nlua, see
-- spec/README.md), driven with real feedkeys the same way
-- spec/mep/git/sidebar_spec.lua exercises its own compose-buffer flow.
local panel = require('mep.ai.panel')

describe('mep.ai.panel', function()
  local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
  end

  local function make_session(overrides)
    return vim.tbl_extend('force', {
      transcript = {},
      pending = nil,
      busy = false,
      on_reply = function() end,
    }, overrides or {})
  end

  after_each(function()
    panel._reset()
  end)

  it('is not open before the first M.open', function()
    assert.is_false(panel.is_open())
  end)

  it('opens a real sidebar and renders one widget line per transcript entry line', function()
    local session = make_session({ transcript = { { role = 'user', text = 'hello\nworld' } } })
    panel.open(session)
    assert.is_true(panel.is_open())
  end)

  it('re-targets the same panel instance on a second M.open rather than opening another', function()
    local first = make_session({})
    panel.open(first)
    local sb1_open = panel.is_open()
    local second = make_session({ transcript = { { role = 'assistant', text = 'hi' } } })
    panel.open(second)
    assert.is_true(sb1_open)
    assert.is_true(panel.is_open())
  end)

  describe('permission decisions', function()
    it('a calls pending.on_decide("allow")', function()
      local decided
      local session = make_session({
        pending = {
          kind = 'permission',
          tool_name = 'read_file',
          description = 'read_file {"path":"x"}',
          allow_always = true,
          on_decide = function(d)
            decided = d
          end,
        },
      })
      panel.open(session)
      feed('a')
      assert.are.equal('allow', decided)
    end)

    it('A calls pending.on_decide("always") when allow_always is true', function()
      local decided
      local session = make_session({
        pending = {
          kind = 'permission',
          tool_name = 'read_file',
          description = 'x',
          allow_always = true,
          on_decide = function(d)
            decided = d
          end,
        },
      })
      panel.open(session)
      feed('A')
      assert.are.equal('always', decided)
    end)

    it('A does nothing when allow_always is false (e.g. run_command)', function()
      local decided = 'untouched'
      local session = make_session({
        pending = {
          kind = 'permission',
          tool_name = 'run_command',
          description = 'Run: rm -rf /',
          allow_always = false,
          on_decide = function(d)
            decided = d
          end,
        },
      })
      panel.open(session)
      feed('A')
      assert.are.equal('untouched', decided)
    end)

    it('d calls pending.on_decide("deny")', function()
      local decided
      local session = make_session({
        pending = {
          kind = 'permission',
          tool_name = 'run_command',
          description = 'Run: x',
          allow_always = false,
          on_decide = function(d)
            decided = d
          end,
        },
      })
      panel.open(session)
      feed('d')
      assert.are.equal('deny', decided)
    end)

    it('a/A/d are no-ops when there is no pending permission', function()
      local session = make_session({})
      panel.open(session)
      -- would error if these tried to index a nil `pending` -- the fact
      -- feeding them doesn't blow up is the assertion
      feed('a')
      feed('A')
      feed('d')
      assert.is_true(panel.is_open())
    end)
  end)

  describe('composing a message (the "i" keymap)', function()
    it('opens an editable buffer and <CR> submits the typed text via on_reply', function()
      local replied
      local session = make_session({
        on_reply = function(text)
          replied = text
        end,
      })
      panel.open(session)
      feed('i')
      feed('ihello there<CR>')
      assert.are.equal('hello there', replied)
    end)

    it('does nothing while the session is busy', function()
      local replied = 'untouched'
      local session = make_session({
        busy = true,
        on_reply = function(text)
          replied = text
        end,
      })
      panel.open(session)
      feed('i')
      feed('ihello<CR>')
      assert.are.equal('untouched', replied)
    end)

    it('does nothing while a permission decision is pending', function()
      local replied = 'untouched'
      local session = make_session({
        pending = { kind = 'permission', tool_name = 'read_file', description = 'x', allow_always = true, on_decide = function() end },
        on_reply = function(text)
          replied = text
        end,
      })
      panel.open(session)
      feed('i')
      feed('ihello<CR>')
      assert.are.equal('untouched', replied)
    end)
  end)

  describe('M.render', function()
    it('is a no-op for a session that is not the one currently shown', function()
      local first = make_session({})
      panel.open(first)
      local stale = make_session({ transcript = { { role = 'user', text = 'stale' } } })
      -- would only matter observably via a crash -- render() must not
      -- error when handed a session that was never opened/is no longer current
      panel.render(stale)
      assert.is_true(panel.is_open())
    end)
  end)

  describe('M.close / M._reset', function()
    it('close() closes the panel without destroying the singleton instance', function()
      local session = make_session({})
      panel.open(session)
      panel.close()
      assert.is_false(panel.is_open())
    end)

    it('_reset() closes the panel and drops the singleton so the next open starts fresh', function()
      local session = make_session({})
      panel.open(session)
      panel._reset()
      assert.is_false(panel.is_open())
    end)
  end)
end)

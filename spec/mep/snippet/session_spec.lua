local session = require('mep.snippet.session')

-- Normal-mode nvim_win_set_cursor clamps to the last real character (one
-- short of "one past the end"), so a cursor genuinely sitting right
-- after the last typed character needs to be set while briefly in
-- Insert mode — same technique spec/mep/completion/engine_spec.lua's
-- own set_cursor_after uses.
local function make_buf_win(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 40, height = 5 })
  return buf, win
end

local function set_cursor_after(win, lnum, col)
  vim.cmd('startinsert')
  vim.api.nvim_win_set_cursor(win, { lnum, col })
  vim.cmd('stopinsert')
end

describe('mep.snippet.session', function()
  after_each(function()
    session._reset()
    -- A few tests below keep Insert mode active (via startinsert) across
    -- an assertion so an end-of-line tabstop's column isn't clamped away
    -- by Normal-mode cursor rules; a failed assertion would otherwise
    -- skip that test's own stopinsert and leak Insert mode into every
    -- later spec file sharing this busted run.
    pcall(vim.cmd, 'stopinsert')
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  describe('expand', function()
    it('replaces the trigger and renders the snippet body into the buffer', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)

      session.expand(buf, win, 2, 'function $1($2)\n\t$0\nend')

      assert.are.same({ 'function ()', '\t', 'end' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('jumps to the first tabstop', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)

      session.expand(buf, win, 2, 'function $1($2)\n\t$0\nend')

      assert.are.same({ 1, 9 }, vim.api.nvim_win_get_cursor(win))
      assert.is_true(session.is_active())
    end)

    it('preserves text before and after the replaced trigger on the same line', function()
      local buf, win = make_buf_win({ 'xx fn yy' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 5) -- right after "xx fn"

      session.expand(buf, win, 2, 'F$1')

      assert.are.same({ 'xx F yy' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('synthesizes an exit stop at the end when the body has no $0', function()
      local buf, win = make_buf_win({ 'ab' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)

      -- The exit stop lands one-past-the-last-character — a position
      -- Normal-mode nvim_win_set_cursor (what this test would otherwise
      -- be in, outside real interactive typing) clamps away; kept in
      -- Insert mode (same as the real <Tab> keymap this exercises,
      -- which only ever runs from inside genuine Insert mode) so it
      -- lands exactly where mep.snippet.session put it.
      vim.cmd('startinsert')
      session.expand(buf, win, 2, '$1 end')
      assert.is_true(session.is_active())
      session.jump(1) -- to the synthesized exit stop
      assert.is_false(session.is_active())
      assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(win)) -- end of " end"
      vim.cmd('stopinsert')
    end)

    it('cancels any previously active session', function()
      local buf, win = make_buf_win({ 'a b' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 1)
      session.expand(buf, win, 1, '$1')
      assert.is_true(session.is_active())

      set_cursor_after(win, 1, 3)
      session.expand(buf, win, 1, '$1')
      assert.is_true(session.is_active())
    end)
  end)

  describe('jump', function()
    it('visits tabstops in ascending index order, $0 last regardless of textual position', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      -- $0 written textually before $1 — still visited last.
      session.expand(buf, win, 2, '$0-$1-')

      assert.are.same({ 1, 1 }, vim.api.nvim_win_get_cursor(win)) -- landed on $1 first
      session.jump(1)
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win)) -- then $0
      assert.is_false(session.is_active())
    end)

    it('visits a repeated same-index tabstop independently, not mirrored', function()
      local buf, win = make_buf_win({ 'x' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 1)
      -- The second occurrence lands one-past-the-last-character — see
      -- the "synthesizes an exit stop" test above for why Insert mode
      -- has to stay active across the jump for that column to land
      -- exactly (not get clamped back a column, Normal-mode's own
      -- behavior).
      vim.cmd('startinsert')
      session.expand(buf, win, 1, '$1-$1')

      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
      assert.is_true(session.jump(1))
      assert.are.same({ 1, 1 }, vim.api.nvim_win_get_cursor(win))
      assert.is_true(session.is_active()) -- one more stop left: the synthesized $0
      session.jump(1)
      assert.is_false(session.is_active())
      vim.cmd('stopinsert')
    end)

    it('jumps backward to a previous tabstop', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      session.expand(buf, win, 2, '$1-$2')

      session.jump(1) -- now on $2
      local ok = session.jump(-1) -- back to $1
      assert.is_true(ok)
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('returns false and does nothing when there is no active session', function()
      assert.is_false(session.jump(1))
    end)

    it('returns false when moving before the first tabstop', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      session.expand(buf, win, 2, '$1-$2')
      assert.is_false(session.jump(-1))
    end)
  end)

  describe('cancel', function()
    it('deactivates the session without altering buffer text', function()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      session.expand(buf, win, 2, '$1-$2')
      session.cancel()
      assert.is_false(session.is_active())
      assert.are.same({ '-' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('is a no-op when there is no active session', function()
      assert.has_no.errors(function()
        session.cancel()
      end)
    end)
  end)
end)

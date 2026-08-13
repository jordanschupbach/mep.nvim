local timestamp = require('mep.org.timestamp')

describe('mep.org.timestamp', function()
  describe('find', function()
    it('finds an active timestamp', function()
      local s, e, t = timestamp.find('* Task <2024-01-01 Mon>')
      assert.are.equal('<2024-01-01 Mon>', ('* Task <2024-01-01 Mon>'):sub(s, e))
      assert.is_true(t.active)
      assert.are.equal(2024, t.year)
      assert.are.equal(1, t.month)
      assert.are.equal(1, t.day)
      assert.are.equal('Mon', t.dow)
    end)

    it('finds an inactive timestamp', function()
      local s, e, t = timestamp.find('logged [2024-01-01 Mon]')
      assert.are.equal('[2024-01-01 Mon]', ('logged [2024-01-01 Mon]'):sub(s, e))
      assert.is_false(t.active)
    end)

    it('parses a time', function()
      local _, _, t = timestamp.find('<2024-01-01 Mon 09:30>')
      assert.are.equal(9, t.hour)
      assert.are.equal(30, t.min)
      assert.is_nil(t.end_hour)
    end)

    it('parses a time range', function()
      local _, _, t = timestamp.find('<2024-01-01 Mon 09:30-10:45>')
      assert.are.equal(9, t.hour)
      assert.are.equal(30, t.min)
      assert.are.equal(10, t.end_hour)
      assert.are.equal(45, t.end_min)
    end)

    it('parses a repeater with no time', function()
      local _, _, t = timestamp.find('<2024-01-01 Mon +1w>')
      assert.are.equal('+1w', t.repeater)
    end)

    it('parses a repeater after a time', function()
      local _, _, t = timestamp.find('<2024-01-01 Mon 09:00 ++2d>')
      assert.are.equal(9, t.hour)
      assert.are.equal('++2d', t.repeater)
    end)

    it('parses a catch-up repeater (.+)', function()
      local _, _, t = timestamp.find('<2024-01-01 Mon .+1m>')
      assert.are.equal('.+1m', t.repeater)
    end)

    it('finds the earliest of two timestamps on one line', function()
      local s = timestamp.find('SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>')
      assert.are.equal(12, s)
    end)

    it('finds a later timestamp when searching from an init offset', function()
      local line = 'SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>'
      local s1, e1 = timestamp.find(line)
      local s2, _, t2 = timestamp.find(line, e1 + 1)
      assert.is_true(s2 > e1)
      assert.are.equal(5, t2.day)
    end)

    it('returns nil when there is no timestamp', function()
      assert.is_nil(timestamp.find('just a plain line'))
    end)

    it('does not mistake a checkbox or priority cookie for a timestamp', function()
      assert.is_nil(timestamp.find('- [ ] item'))
      assert.is_nil(timestamp.find('* [#A] Task'))
    end)
  end)

  describe('find_at_col', function()
    local LINE = 'text <2024-01-01 Mon> more'

    it('finds the timestamp containing the column', function()
      local s, e, t = timestamp.find_at_col(LINE, 6) -- inside "<2024..."
      assert.are.equal(2024, t.year)
      assert.are.equal(6, s) -- 1-based position of "<"
      assert.are.equal(21, e) -- 1-based position of ">"
    end)

    it('returns nil for a column outside any timestamp', function()
      assert.is_nil(timestamp.find_at_col(LINE, 0))
      assert.is_nil(timestamp.find_at_col(LINE, #LINE - 1))
    end)
  end)

  describe('parse', function()
    it('parses a standalone timestamp string', function()
      local t = timestamp.parse('<2024-01-01 Mon>')
      assert.are.equal(2024, t.year)
    end)

    it('returns nil for text with a timestamp plus extra content', function()
      assert.is_nil(timestamp.parse('<2024-01-01 Mon> extra'))
    end)

    it('returns nil for non-timestamp text', function()
      assert.is_nil(timestamp.parse('not a timestamp'))
    end)
  end)

  describe('render', function()
    it('round-trips a bare date', function()
      local original = '<2024-01-01 Mon>'
      assert.are.equal(original, timestamp.render(timestamp.parse(original)))
    end)

    it('round-trips an inactive timestamp', function()
      local original = '[2024-01-01 Mon]'
      assert.are.equal(original, timestamp.render(timestamp.parse(original)))
    end)

    it('round-trips a time range with a repeater', function()
      local original = '<2024-01-01 Mon 09:00-10:30 +1w>'
      assert.are.equal(original, timestamp.render(timestamp.parse(original)))
    end)
  end)

  describe('today', function()
    it('defaults to active', function()
      assert.is_true(timestamp.today().active)
    end)

    it('honors an explicit active = false', function()
      assert.is_false(timestamp.today(false).active)
    end)

    it('produces a self-consistent, re-parseable timestamp', function()
      local t = timestamp.today()
      local reparsed = timestamp.parse(timestamp.render(t))
      assert.are.same(t, reparsed)
    end)
  end)

  describe('now', function()
    it('includes the current hour/minute alongside today`s date', function()
      local t = timestamp.now()
      local d = os.date('*t')
      assert.are.equal(d.year, t.year)
      assert.are.equal(d.month, t.month)
      assert.are.equal(d.day, t.day)
      assert.are.equal(d.hour, t.hour)
      assert.are.equal(d.min, t.min)
    end)

    it('defaults to active', function()
      assert.is_true(timestamp.now().active)
    end)

    it('honors an explicit active = false', function()
      assert.is_false(timestamp.now(false).active)
    end)

    it('produces a self-consistent, re-parseable timestamp', function()
      local t = timestamp.now()
      local reparsed = timestamp.parse(timestamp.render(t))
      assert.are.same(t, reparsed)
    end)
  end)

  describe('add_days', function()
    it('rolls over a month boundary and recomputes the weekday', function()
      -- verified against the real calendar: 2024-01-31 + 1 day = 2024-02-01,
      -- and 2024-02-01 is a real, independently-checked Thursday
      local t = { active = true, year = 2024, month = 1, day = 31, dow = 'Wed' }
      local result = timestamp.add_days(t, 1)
      assert.are.equal(2024, result.year)
      assert.are.equal(2, result.month)
      assert.are.equal(1, result.day)
      assert.are.equal('Thu', result.dow)
    end)

    it('goes backwards across a year boundary', function()
      local t = { active = true, year = 2024, month = 1, day = 1, dow = 'Mon' }
      local result = timestamp.add_days(t, -1)
      assert.are.equal(2023, result.year)
      assert.are.equal(12, result.month)
      assert.are.equal(31, result.day)
    end)

    it('preserves the weekday when shifting by exactly one week', function()
      local t = timestamp.today(true)
      local result = timestamp.add_days(t, 7)
      assert.are.equal(t.dow, result.dow)
    end)

    it('does not mutate the input table', function()
      local t = { active = true, year = 2024, month = 1, day = 1, dow = 'Mon' }
      timestamp.add_days(t, 1)
      assert.are.equal(1, t.day)
    end)
  end)

  describe('to_input_string / parse_user_input round-trip', function()
    it('round-trips a bare date', function()
      local t = timestamp.parse('<2024-01-01 Mon>')
      local input_str = timestamp.to_input_string(t)
      assert.are.equal('2024-01-01', input_str)
      local reparsed = timestamp.parse_user_input(input_str, true)
      assert.are.equal(2024, reparsed.year)
      assert.are.equal('Mon', reparsed.dow) -- recomputed, not copied
    end)

    it('round-trips a date with time', function()
      local t = timestamp.parse('<2024-01-01 Mon 09:30>')
      local input_str = timestamp.to_input_string(t)
      assert.are.equal('2024-01-01 09:30', input_str)
      local reparsed = timestamp.parse_user_input(input_str, true)
      assert.are.equal(9, reparsed.hour)
      assert.are.equal(30, reparsed.min)
    end)

    it('rejects malformed input', function()
      assert.is_nil(timestamp.parse_user_input('not a date', true))
      assert.is_nil(timestamp.parse_user_input('2024-01-01 nope', true))
    end)

    it('sets active from the argument, not the input text', function()
      local t = timestamp.parse_user_input('2024-01-01', false)
      assert.is_false(t.active)
    end)
  end)

  describe('insert_or_edit', function()
    local function make_win(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    -- nvim_win_set_cursor clamps the column to the last valid character
    -- in normal-mode buffer state, so landing the cursor one-past-the-end
    -- (right after a trailing space, as real typing would leave it)
    -- requires briefly entering insert mode first.
    local function set_cursor_at_end(win, lnum, col)
      vim.api.nvim_set_current_win(win)
      vim.cmd('startinsert')
      vim.api.nvim_win_set_cursor(win, { lnum, col })
      vim.cmd('stopinsert')
    end

    it('inserts a new active timestamp at the cursor', function()
      local buf, win = make_win({ 'Task ' })
      set_cursor_at_end(win, 1, 5)
      vim.ui.input = function(opts, on_confirm)
        on_confirm('2024-01-01')
      end
      timestamp.insert_or_edit(buf, win, true)
      assert.are.equal('Task <2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('inserts an inactive timestamp when active = false', function()
      local buf, win = make_win({ 'Task ' })
      set_cursor_at_end(win, 1, 5)
      vim.ui.input = function(opts, on_confirm)
        on_confirm('2024-01-01')
      end
      timestamp.insert_or_edit(buf, win, false)
      assert.are.equal('Task [2024-01-01 Mon]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('edits the existing timestamp under the cursor, preserving its active/inactive-ness', function()
      local buf, win = make_win({ 'Task [2024-01-01 Mon]' })
      vim.api.nvim_win_set_cursor(win, { 1, 8 }) -- inside the bracketed span
      local prompt_opts
      vim.ui.input = function(opts, on_confirm)
        prompt_opts = opts
        on_confirm('2024-06-15')
      end
      timestamp.insert_or_edit(buf, win, true) -- active=true requested, but editing existing inactive one
      assert.are.equal('2024-01-01', prompt_opts.default)
      assert.are.equal('Task [2024-06-15 Sat]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('does nothing when the prompt is cancelled', function()
      local buf, win = make_win({ 'Task ' })
      vim.api.nvim_win_set_cursor(win, { 1, 5 })
      vim.ui.input = function(opts, on_confirm)
        on_confirm(nil)
      end
      timestamp.insert_or_edit(buf, win, true)
      assert.are.equal('Task ', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('adjust_under_cursor', function()
    local function make_win(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('advances the date under the cursor by delta days', function()
      local buf, win = make_win({ '<2024-01-01 Mon>' })
      vim.api.nvim_win_set_cursor(win, { 1, 5 })
      local ok = timestamp.adjust_under_cursor(buf, win, 1)
      assert.is_true(ok)
      assert.are.equal('<2024-01-02 Tue>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('goes backwards with a negative delta', function()
      local buf, win = make_win({ '<2024-01-02 Tue>' })
      vim.api.nvim_win_set_cursor(win, { 1, 5 })
      timestamp.adjust_under_cursor(buf, win, -1)
      assert.are.equal('<2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('adjusts by a week with delta = 7', function()
      local buf, win = make_win({ '<2024-01-01 Mon>' })
      vim.api.nvim_win_set_cursor(win, { 1, 5 })
      timestamp.adjust_under_cursor(buf, win, 7)
      assert.are.equal('<2024-01-08 Mon>', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns false and does nothing when the cursor is not on a timestamp', function()
      local buf, win = make_win({ 'no timestamp here' })
      vim.api.nvim_win_set_cursor(win, { 1, 3 })
      local ok = timestamp.adjust_under_cursor(buf, win, 1)
      assert.is_false(ok)
      assert.are.equal('no timestamp here', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)
end)

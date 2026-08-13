local clock = require('mep.org.clock')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.clock', function()
  describe('find_logbook', function()
    it('finds the drawer right after a headline with no plan/properties', function()
      local buf = make_buf({ '* Task', ':LOGBOOK:', 'CLOCK: [2024-01-01 Mon 09:00]', ':END:' })
      local start, stop = clock.find_logbook(buf, 1)
      assert.are.equal(2, start)
      assert.are.equal(4, stop)
    end)

    it('skips a planning line', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', ':LOGBOOK:', ':END:' })
      local start = clock.find_logbook(buf, 1)
      assert.are.equal(3, start)
    end)

    it('skips a properties drawer', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:', ':LOGBOOK:', ':END:' })
      local start = clock.find_logbook(buf, 1)
      assert.are.equal(5, start)
    end)

    it('skips both a planning line and a properties drawer', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', ':PROPERTIES:', ':ID: 1', ':END:', ':LOGBOOK:', ':END:' })
      local start = clock.find_logbook(buf, 1)
      assert.are.equal(6, start)
    end)

    it('returns nil when there is no logbook', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:', 'body' })
      assert.is_nil(clock.find_logbook(buf, 1))
    end)
  end)

  describe('current_clock', function()
    it('finds an open clock line anywhere in the buffer', function()
      local buf = make_buf({ '* Task', ':LOGBOOK:', 'CLOCK: [2024-01-01 Mon 09:00]', ':END:' })
      local c = clock.current_clock(buf)
      assert.are.equal(3, c.lnum)
      assert.are.equal('[2024-01-01 Mon 09:00]', c.start_text)
      assert.are.equal(1, c.headline)
    end)

    it('ignores a closed clock line', function()
      local buf = make_buf({ '* Task', ':LOGBOOK:', 'CLOCK: [2024-01-01 Mon 09:00]--[2024-01-01 Mon 10:00] => 1:00', ':END:' })
      assert.is_nil(clock.current_clock(buf))
    end)

    it('returns nil when nothing is clocked in', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(clock.current_clock(buf))
    end)
  end)

  describe('diff_minutes', function()
    it('computes whole minutes between two timestamps', function()
      local t1 = { year = 2024, month = 1, day = 1, hour = 9, min = 0 }
      local t2 = { year = 2024, month = 1, day = 1, hour = 10, min = 30 }
      assert.are.equal(90, clock.diff_minutes(t1, t2))
    end)

    it('handles a day rollover', function()
      local t1 = { year = 2024, month = 1, day = 1, hour = 23, min = 30 }
      local t2 = { year = 2024, month = 1, day = 2, hour = 0, min = 15 }
      assert.are.equal(45, clock.diff_minutes(t1, t2))
    end)
  end)

  describe('clock_in', function()
    it('creates a :LOGBOOK: drawer with an open CLOCK entry', function()
      local buf = make_buf({ '* Task', 'body' })
      local rendered = clock.clock_in(buf, 1)
      assert.matches('^CLOCK: %[%d%d%d%d%-%d%d%-%d%d %a+ %d%d:%d%d%]$', rendered)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('* Task', lines[1])
      assert.are.equal(':LOGBOOK:', lines[2])
      assert.are.equal(rendered, lines[3])
      assert.are.equal(':END:', lines[4])
      assert.are.equal('body', lines[5])
    end)

    it('inserts as the first entry of an existing logbook', function()
      local buf = make_buf({
        '* Task',
        ':LOGBOOK:',
        'CLOCK: [2024-01-01 Mon 08:00]--[2024-01-01 Mon 09:00] => 1:00',
        ':END:',
      })
      clock.clock_in(buf, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.matches('^CLOCK: %[', lines[3])
      assert.matches('=> 1:00$', lines[4])
    end)

    it('creates the drawer after an existing properties drawer', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:' })
      clock.clock_in(buf, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(':END:', lines[4]) -- properties drawer's own :END:
      assert.are.equal(':LOGBOOK:', lines[5])
    end)

    it('refuses to clock in twice', function()
      local buf = make_buf({ '* Task' })
      clock.clock_in(buf, 1)
      local result = clock.clock_in(buf, 1)
      assert.is_nil(result)
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(clock.clock_in(buf, 1))
    end)
  end)

  describe('clock_out', function()
    it('closes the open clock with an end timestamp and duration', function()
      local buf = make_buf({ '* Task' })
      clock.clock_in(buf, 1)
      local duration = clock.clock_out(buf)
      assert.matches('^%d+:%d%d$', duration)
      local line = clock.current_clock(buf)
      assert.is_nil(line) -- no longer open
      local rendered = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
      assert.matches('^CLOCK: %[.-%]%-%-%[.-%] => %d+:%d%d$', rendered)
    end)

    it('returns nil when nothing is clocked in', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(clock.clock_out(buf))
    end)
  end)

  describe('status', function()
    it('returns a "Title (H:MM)" string for the clocked-in task', function()
      local buf = make_buf({ '* TODO My Task' })
      clock.clock_in(buf, 1, { 'TODO', 'DONE' })
      local status = clock.status(buf, { 'TODO', 'DONE' })
      assert.matches('^My Task %(%d+:%d%d%)$', status)
    end)

    it('returns nil when nothing is clocked in', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(clock.status(buf, {}))
    end)
  end)

  describe('parse_duration', function()
    it('parses H:MM', function()
      assert.are.equal(90, clock.parse_duration('1:30'))
    end)

    it('parses bare minutes', function()
      assert.are.equal(45, clock.parse_duration('45'))
    end)

    it('returns nil for malformed text', function()
      assert.is_nil(clock.parse_duration('not a duration'))
    end)

    it('returns nil for nil input', function()
      assert.is_nil(clock.parse_duration(nil))
    end)
  end)

  describe('effort', function()
    it('reads the Effort: property as minutes', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':Effort: 1:30', ':END:' })
      assert.are.equal(90, clock.effort(buf, 1))
    end)

    it('returns nil when there is no Effort property', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(clock.effort(buf, 1))
    end)
  end)

  describe('report / render_table / find_clocktable / insert_report', function()
    local SAMPLE = {
      '* Grandparent',
      '** Parent',
      'CLOCK: [2024-01-01 Mon 08:00]--[2024-01-01 Mon 09:00] => 1:00',
      '*** Child',
      'CLOCK: [2024-01-01 Mon 09:00]--[2024-01-01 Mon 09:30] => 0:30',
      '* Unrelated',
    }

    it('computes recursive totals per headline', function()
      local buf = make_buf(SAMPLE)
      local rows = clock.report(buf)
      local by_title = {}
      for _, r in ipairs(rows) do
        by_title[r.title] = r.minutes
      end
      assert.are.equal(30, by_title['Child'])
      assert.are.equal(90, by_title['Parent']) -- own 60 + child's 30
      assert.are.equal(90, by_title['Grandparent']) -- no own clocks, just descendants'
      assert.is_nil(by_title['Unrelated'])
    end)

    it('renders a table with indentation by level', function()
      local buf = make_buf(SAMPLE)
      local rendered = clock.render_table(clock.report(buf))
      assert.are.equal('#+BEGIN: clocktable', rendered[1])
      assert.are.equal('| Headline | Time |', rendered[2])
      assert.are.equal('|--', rendered[3])
      assert.matches('Grandparent | 1:30', rendered[4])
      assert.matches('  Parent | 1:30', rendered[5])
      assert.matches('    Child | 0:30', rendered[6])
      assert.are.equal('#+END:', rendered[#rendered])
    end)

    it('inserts a new report at the given line when none exists', function()
      local buf = make_buf({ '* Task', 'CLOCK: [2024-01-01 Mon 08:00]--[2024-01-01 Mon 09:00] => 1:00' })
      clock.insert_report(buf, 2)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('#+BEGIN: clocktable', lines[3])
    end)

    it('refreshes an existing report in place', function()
      local buf = make_buf({
        '* Task',
        'CLOCK: [2024-01-01 Mon 08:00]--[2024-01-01 Mon 09:00] => 1:00',
        '#+BEGIN: clocktable',
        '| stale |',
        '#+END:',
      })
      clock.insert_report(buf, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- 2 unchanged lines + a full 5-line rendered table (BEGIN, header,
      -- separator, 1 data row, END) replacing the old 3-line stale block
      assert.are.equal(7, #lines)
      assert.matches('Task | 1:00', lines[6])
    end)

    it('find_clocktable returns nil when there is no block', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(clock.find_clocktable(buf, 1))
    end)
  end)
end)

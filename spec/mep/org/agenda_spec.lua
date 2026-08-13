local agenda = require('mep.org.agenda')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function ts(year, month, day, repeater)
  return { active = true, year = year, month = month, day = day, dow = 'Mon', repeater = repeater }
end

describe('mep.org.agenda', function()
  describe('files', function()
    local tmpdir
    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)
    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('returns a literal file path unchanged', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* Task' }, path)
      assert.are.same({ path }, agenda.files({ path }))
    end)

    it('expands a glob pattern to every matching file, sorted', function()
      vim.fn.writefile({}, tmpdir .. '/b.org')
      vim.fn.writefile({}, tmpdir .. '/a.org')
      local result = agenda.files({ tmpdir .. '/*.org' })
      assert.are.same({ tmpdir .. '/a.org', tmpdir .. '/b.org' }, result)
    end)

    it('dedupes files matched by more than one pattern', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({}, path)
      local result = agenda.files({ path, tmpdir .. '/*.org' })
      assert.are.same({ path }, result)
    end)

    it('ignores a pattern matching nothing', function()
      assert.are.same({}, agenda.files({ tmpdir .. '/nope-*.org' }))
    end)

    it('returns {} for an empty/nil config', function()
      assert.are.same({}, agenda.files(nil))
      assert.are.same({}, agenda.files({}))
    end)
  end)

  describe('collect_entries', function()
    local tmpdir
    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
    end)
    after_each(function()
      vim.fn.delete(tmpdir, 'rf')
    end)

    it('collects headline, todo, tags, scheduled, and deadline', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({
        '* TODO Task :work:',
        'SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>',
      }, path)
      local entries = agenda.collect_entries({ path }, { 'TODO', 'DONE' })
      assert.are.equal(1, #entries)
      local e = entries[1]
      assert.are.equal('TODO', e.todo)
      assert.are.equal('Task', e.title)
      assert.are.same({ 'work' }, e.tags)
      assert.are.equal(1, e.scheduled.day)
      assert.are.equal(5, e.deadline.day)
      assert.are.equal(path, e.file)
    end)

    it('collects a plain headline with neither scheduled nor deadline', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* Just a task' }, path)
      local entries = agenda.collect_entries({ path }, {})
      assert.is_nil(entries[1].scheduled)
      assert.is_nil(entries[1].deadline)
    end)

    it('collects across multiple files', function()
      local path1 = tmpdir .. '/a.org'
      local path2 = tmpdir .. '/b.org'
      vim.fn.writefile({ '* Task A' }, path1)
      vim.fn.writefile({ '* Task B' }, path2)
      local entries = agenda.collect_entries({ path1, path2 }, {})
      assert.are.equal(2, #entries)
    end)

    it('sees live unsaved buffer content, not just what is on disk', function()
      local path = tmpdir .. '/notes.org'
      vim.fn.writefile({ '* On disk' }, path)
      local bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Edited in buffer' })
      local entries = agenda.collect_entries({ path }, {})
      assert.are.equal('Edited in buffer', entries[1].title)
    end)
  end)

  describe('occurs_on', function()
    it('matches the exact base date with no repeater', function()
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 1), nil))
    end)

    it('does not match a different date with no repeater', function()
      assert.is_false(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 2), nil))
    end)

    it('matches a daily repeater on the right cadence', function()
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 3), '+2d'))
      assert.is_false(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 2), '+2d'))
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 5), '+2d'))
    end)

    it('matches a weekly repeater on the right cadence', function()
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 8), '+1w'))
      assert.is_false(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 4), '+1w'))
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 15), '+1w'))
    end)

    it('matches a monthly repeater by same day-of-month', function()
      assert.is_true(agenda.occurs_on(ts(2024, 1, 15), ts(2024, 2, 15), '+1m'))
      assert.is_false(agenda.occurs_on(ts(2024, 1, 15), ts(2024, 2, 16), '+1m'))
      assert.is_true(agenda.occurs_on(ts(2024, 1, 15), ts(2024, 4, 15), '+3m'))
    end)

    it('matches a yearly repeater by same day/month', function()
      assert.is_true(agenda.occurs_on(ts(2024, 3, 10), ts(2026, 3, 10), '+1y'))
      assert.is_false(agenda.occurs_on(ts(2024, 3, 10), ts(2026, 3, 11), '+1y'))
    end)

    it('treats ++ and .+ cadences the same as + for matching purposes', function()
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 8), '++1w'))
      assert.is_true(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 8), '.+1w'))
    end)

    it('never matches a target before the base date', function()
      assert.is_false(agenda.occurs_on(ts(2024, 1, 10), ts(2024, 1, 1), '+1d'))
    end)

    it('returns false for a malformed repeater', function()
      assert.is_false(agenda.occurs_on(ts(2024, 1, 1), ts(2024, 1, 5), 'nonsense'))
    end)
  end)

  describe('entries_for_date', function()
    it('includes an entry scheduled exactly on the date', function()
      local entries = { { scheduled = ts(2024, 1, 1), deadline = nil } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1))
      assert.are.equal(1, #occ)
      assert.are.equal('scheduled', occ[1].kind)
      assert.are.equal(0, occ[1].days_until)
    end)

    it('includes an entry with a deadline exactly on the date', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 1) } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1))
      assert.are.equal('deadline', occ[1].kind)
      assert.are.equal(0, occ[1].days_until)
    end)

    it('can produce two occurrences for one entry (scheduled today AND deadline warning)', function()
      local entries = { { scheduled = ts(2024, 1, 1), deadline = ts(2024, 1, 5) } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1), 14)
      assert.are.equal(2, #occ)
    end)

    it('includes an upcoming deadline within warning_days, with days_until set', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 10) } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1), 14)
      assert.are.equal(1, #occ)
      assert.are.equal(9, occ[1].days_until)
    end)

    it('excludes a deadline beyond warning_days', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 20) } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1), 5)
      assert.are.equal(0, #occ)
    end)

    it('excludes deadline warnings entirely when warning_days is nil', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 10) } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 1))
      assert.are.equal(0, #occ)
    end)

    it('includes an overdue non-repeating deadline only when include_overdue is true', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 1) } }
      local occ_without = agenda.entries_for_date(entries, ts(2024, 1, 5), nil, false)
      assert.are.equal(0, #occ_without)
      local occ_with = agenda.entries_for_date(entries, ts(2024, 1, 5), nil, true)
      assert.are.equal(1, #occ_with)
      assert.are.equal(-4, occ_with[1].days_until)
    end)

    it('does not treat a repeating deadline as overdue', function()
      local entries = { { scheduled = nil, deadline = ts(2024, 1, 1, '+1w') } }
      local occ = agenda.entries_for_date(entries, ts(2024, 1, 3), nil, true)
      assert.are.equal(0, #occ)
    end)

    it('produces no occurrences for an entry with neither scheduled nor deadline', function()
      local occ = agenda.entries_for_date({ {} }, ts(2024, 1, 1))
      assert.are.equal(0, #occ)
    end)
  end)

  describe('todo_view', function()
    it('includes entries with a non-done todo keyword', function()
      local entries = { { todo = 'TODO' }, { todo = 'DOING' }, { todo = 'DONE' }, { todo = nil } }
      local out = agenda.todo_view(entries, { 'TODO', 'DOING', 'DONE' })
      assert.are.equal(2, #out)
    end)

    it('returns {} when nothing has a todo keyword', function()
      assert.are.same({}, agenda.todo_view({ { todo = nil } }, { 'TODO', 'DONE' }))
    end)
  end)

  describe('tag_search_view', function()
    it('filters entries by tag match expression', function()
      local entries = { { tags = { 'work' } }, { tags = { 'home' } } }
      local out = agenda.tag_search_view(entries, '+work')
      assert.are.equal(1, #out)
      assert.are.same({ 'work' }, out[1].tags)
    end)

    it('returns {} for an invalid expression', function()
      local entries = { { tags = { 'work' } } }
      assert.are.same({}, agenda.tag_search_view(entries, 'not valid'))
    end)
  end)

  describe('render_day', function()
    it('renders a header line and a placeholder when there are no occurrences', function()
      local lines, sources = agenda.render_day(ts(2024, 1, 1), {})
      assert.matches('2024%-01%-01', lines[1])
      assert.are.equal('  (nothing scheduled)', lines[2])
      assert.is_false(sources[1])
      assert.is_false(sources[2])
    end)

    it('renders one line per occurrence with a jumpable source', function()
      local occ = { { entry = { bufnr = 42, lnum = 7, todo = 'TODO', title = 'Task' }, kind = 'scheduled', days_until = 0 } }
      local lines, sources = agenda.render_day(ts(2024, 1, 1), occ)
      assert.matches('Scheduled:', lines[2])
      assert.matches('TODO Task', lines[2])
      assert.are.same({ bufnr = 42, lnum = 7 }, sources[2])
    end)

    it('renders an overdue deadline distinctly', function()
      local occ = { { entry = { bufnr = 1, lnum = 1, title = 'Late' }, kind = 'deadline', days_until = -3 } }
      local lines = agenda.render_day(ts(2024, 1, 1), occ)
      assert.matches('overdue', lines[2])
    end)

    it('renders an upcoming deadline warning distinctly', function()
      local occ = { { entry = { bufnr = 1, lnum = 1, title = 'Soon' }, kind = 'deadline', days_until = 3 } }
      local lines = agenda.render_day(ts(2024, 1, 1), occ)
      assert.matches('in 3d', lines[2])
    end)
  end)

  describe('render_week', function()
    it('renders 7 day-header lines', function()
      local lines = agenda.render_week(ts(2024, 1, 1), {})
      local header_count = 0
      for _, l in ipairs(lines) do
        if l:match('2024%-01%-0%d') or l:match('2024%-01%-1%d') then
          header_count = header_count + 1
        end
      end
      assert.are.equal(7, header_count)
    end)
  end)

  describe('render_entries', function()
    it('renders todo, title, tags, and a jumpable source', function()
      local entries = { { bufnr = 5, lnum = 3, todo = 'TODO', title = 'Task', tags = { 'work' }, file = '/x/notes.org' } }
      local lines, sources = agenda.render_entries(entries)
      assert.matches('TODO Task', lines[1])
      assert.matches(':work:', lines[1])
      assert.matches('notes%.org:3', lines[1])
      assert.are.same({ bufnr = 5, lnum = 3 }, sources[1])
    end)

    it('omits the tags block when there are none', function()
      local entries = { { bufnr = 1, lnum = 1, todo = nil, title = 'Task', tags = {}, file = '/x.org' } }
      local lines = agenda.render_entries(entries)
      assert.are.equal('Task  (x.org:1)', lines[1])
    end)
  end)

  describe('open', function()
    local src_buf

    before_each(function()
      src_buf = make_buf({ '* TODO Task one', '* TODO Task two' })
    end)

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'org-agenda' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      pcall(vim.api.nvim_buf_delete, src_buf, { force = true })
    end)

    it('opens a bottom split with the given lines in a non-modifiable org-agenda buffer', function()
      local buf, win = agenda.open({ 'line1', 'line2' }, { false, false })
      assert.are.equal('org-agenda', vim.bo[buf].filetype)
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].modifiable)
      assert.are.same({ 'line1', 'line2' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    it('<CR> on a jumpable line closes the agenda and jumps to the source', function()
      local prev_win = vim.api.nvim_get_current_win()
      local buf, win = agenda.open({ 'Task one' }, { { bufnr = src_buf, lnum = 1 } })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.are.equal(prev_win, vim.api.nvim_get_current_win())
      assert.are.equal(src_buf, vim.api.nvim_win_get_buf(prev_win))
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(prev_win))
      assert.are.equal(buf, buf)
    end)

    it('<CR> on a non-jumpable line is a no-op', function()
      local buf, win = agenda.open({ 'Header' }, { false })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.are.equal(buf, vim.api.nvim_win_get_buf(win))
    end)

    it('t cycles the TODO state at the source and refreshes the agenda', function()
      local refreshed = false
      local _, win = agenda.open({ 'Task one' }, { { bufnr = src_buf, lnum = 1 } }, {
        todo_keywords = { 'TODO', 'DONE' },
        refresh = function()
          refreshed = true
          return { 'Task one (refreshed)' }, { { bufnr = src_buf, lnum = 1 } }
        end,
      })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('t', true, false, true), 'x', false)
      assert.matches('DONE', vim.api.nvim_buf_get_lines(src_buf, 0, 1, false)[1])
      assert.is_true(refreshed)
      local buf = vim.api.nvim_win_get_buf(win)
      assert.are.same({ 'Task one (refreshed)' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('s calls plan.schedule_interactive with the source location', function()
      local plan_mod = require('mep.org.plan')
      local orig = plan_mod.schedule_interactive
      local captured
      plan_mod.schedule_interactive = function(bufnr, win, lnum)
        captured = { bufnr = bufnr, lnum = lnum }
      end
      local _, win = agenda.open({ 'Task one' }, { { bufnr = src_buf, lnum = 2 } })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('s', true, false, true), 'x', false)
      plan_mod.schedule_interactive = orig
      assert.are.same({ bufnr = src_buf, lnum = 2 }, captured)
    end)

    it('q closes the agenda window', function()
      local _, win = agenda.open({ 'line1' }, { false })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('q', true, false, true), 'x', false)
      assert.is_false(vim.api.nvim_win_is_valid(win))
    end)

    it('q restores focus to the window that opened the agenda, even a floating one', function()
      -- a floating window isn't Neovim's "previous split" once closed,
      -- so this only passes if q explicitly restores prev_win rather
      -- than relying on default close-window focus behavior
      local float_buf = vim.api.nvim_create_buf(false, true)
      local float_win = vim.api.nvim_open_win(float_buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      local _, win = agenda.open({ 'line1' }, { false })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('q', true, false, true), 'x', false)
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.are.equal(float_win, vim.api.nvim_get_current_win())
      pcall(vim.api.nvim_win_close, float_win, true)
    end)
  end)

  describe('show_day / show_week / show_todo_list / show_tag_search', function()
    local tmpdir, path, config

    before_each(function()
      tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, 'p')
      path = tmpdir .. '/notes.org'
      vim.fn.writefile({
        '* TODO Task A :work:',
        'SCHEDULED: <2024-01-01 Mon>',
        '* TODO Task B',
        '* DONE Task C',
      }, path)
      config = { agenda_files = { path }, todo_keywords = { 'TODO', 'DONE' }, deadline_warning_days = 14 }
    end)

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'org-agenda' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      vim.fn.delete(tmpdir, 'rf')
    end)

    local function agenda_win()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'org-agenda' then
          return win
        end
      end
    end

    it('show_day renders the given date`s scheduled occurrences', function()
      agenda.show_day(config, { year = 2024, month = 1, day = 1 })
      local win = agenda_win()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      assert.matches('2024%-01%-01', lines[1])
      assert.matches('TODO Task A', table.concat(lines, '\n'))
    end)

    it('show_week renders 7 days', function()
      agenda.show_week(config, { year = 2024, month = 1, day = 1 })
      local win = agenda_win()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      local header_count = 0
      for _, l in ipairs(lines) do
        if l:match('2024%-01%-0%d') then
          header_count = header_count + 1
        end
      end
      assert.are.equal(7, header_count)
    end)

    it('show_todo_list renders outstanding TODOs but excludes DONE', function()
      agenda.show_todo_list(config)
      local win = agenda_win()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
      assert.matches('Task A', text)
      assert.matches('Task B', text)
      assert.is_nil(text:find('Task C'))
    end)

    it('show_tag_search renders only matching entries', function()
      agenda.show_tag_search(config, '+work')
      local win = agenda_win()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
      assert.matches('Task A', text)
      assert.is_nil(text:find('Task B'))
    end)

    it('show_tag_search_interactive prompts via vim.ui.input then shows the search', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, on_confirm)
        on_confirm('+work')
      end
      agenda.show_tag_search_interactive(config)
      vim.ui.input = orig_input
      local win = agenda_win()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
      assert.matches('Task A', text)
    end)

    it('show_tag_search_interactive does nothing on an empty answer', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, on_confirm)
        on_confirm('')
      end
      agenda.show_tag_search_interactive(config)
      vim.ui.input = orig_input
      assert.is_nil(agenda_win())
    end)

    it('dispatch_interactive prompts via vim.ui.select and opens the chosen view', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(_, _, on_choice)
        on_choice('todo')
      end
      agenda.dispatch_interactive(config)
      vim.ui.select = orig_select
      local win = agenda_win()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
      assert.matches('Task A', text)
    end)

    it('dispatch_interactive opens nothing when the selection is cancelled', function()
      local orig_select = vim.ui.select
      vim.ui.select = function(_, _, on_choice)
        on_choice(nil)
      end
      agenda.dispatch_interactive(config)
      vim.ui.select = orig_select
      assert.is_nil(agenda_win())
    end)
  end)
end)

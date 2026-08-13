local plan = require('mep.org.plan')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.plan', function()
  describe('is_plan_line', function()
    it('recognizes a SCHEDULED line', function()
      assert.is_true(plan.is_plan_line('SCHEDULED: <2024-01-01 Mon>'))
    end)

    it('recognizes a DEADLINE line', function()
      assert.is_true(plan.is_plan_line('DEADLINE: <2024-01-05 Fri>'))
    end)

    it('recognizes leading indentation', function()
      assert.is_true(plan.is_plan_line('  SCHEDULED: <2024-01-01 Mon>'))
    end)

    it('rejects a plain line, nil, or a line that merely mentions the words', function()
      assert.is_false(plan.is_plan_line('just a line'))
      assert.is_false(plan.is_plan_line(nil))
      assert.is_false(plan.is_plan_line('I was SCHEDULED to do something'))
    end)
  end)

  describe('parse', function()
    it('parses a SCHEDULED-only line', function()
      local p = plan.parse('SCHEDULED: <2024-01-01 Mon>')
      assert.are.equal('<2024-01-01 Mon>', p.scheduled)
      assert.is_nil(p.deadline)
    end)

    it('parses a DEADLINE-only line', function()
      local p = plan.parse('DEADLINE: <2024-01-05 Fri>')
      assert.are.equal('<2024-01-05 Fri>', p.deadline)
      assert.is_nil(p.scheduled)
    end)

    it('parses both on one line', function()
      local p = plan.parse('SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>')
      assert.are.equal('<2024-01-01 Mon>', p.scheduled)
      assert.are.equal('<2024-01-05 Fri>', p.deadline)
    end)

    it('parses inactive timestamps too', function()
      local p = plan.parse('SCHEDULED: [2024-01-01 Mon]')
      assert.are.equal('[2024-01-01 Mon]', p.scheduled)
    end)

    it('returns nil for a non-plan line', function()
      assert.is_nil(plan.parse('just a line'))
    end)
  end)

  describe('render', function()
    it('renders SCHEDULED only', function()
      assert.are.equal('SCHEDULED: <2024-01-01 Mon>', plan.render({ scheduled = '<2024-01-01 Mon>' }))
    end)

    it('renders both, SCHEDULED before DEADLINE', function()
      assert.are.equal(
        'SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>',
        plan.render({ scheduled = '<2024-01-01 Mon>', deadline = '<2024-01-05 Fri>' })
      )
    end)

    it('renders an empty string for an empty plan', function()
      assert.are.equal('', plan.render({}))
    end)
  end)

  describe('find', function()
    it('finds the planning line immediately after a headline', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', 'body' })
      assert.are.equal(2, plan.find(buf, 1))
    end)

    it('returns nil when the next line is not a planning line', function()
      local buf = make_buf({ '* Task', 'body' })
      assert.is_nil(plan.find(buf, 1))
    end)

    it('returns nil at the last line of the buffer', function()
      local buf = make_buf({ '* Task' })
      assert.is_nil(plan.find(buf, 1))
    end)
  end)

  describe('set_scheduled / set_deadline', function()
    it('creates a new planning line right after the headline', function()
      local buf = make_buf({ '* Task', 'body' })
      plan.set_scheduled(buf, 1, '<2024-01-01 Mon>')
      assert.are.same({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', 'body' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('adds DEADLINE to an existing SCHEDULED line rather than duplicating it', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>' })
      plan.set_deadline(buf, 1, '<2024-01-05 Fri>')
      assert.are.same({ '* Task', 'SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('replaces an existing SCHEDULED timestamp', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>' })
      plan.set_scheduled(buf, 1, '<2024-06-15 Sat>')
      assert.are.equal('SCHEDULED: <2024-06-15 Sat>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('operates relative to the enclosing headline, not just an exact headline line', function()
      local buf = make_buf({ '* Task', 'body' })
      plan.set_scheduled(buf, 2, '<2024-01-01 Mon>')
      assert.are.equal('SCHEDULED: <2024-01-01 Mon>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(plan.set_scheduled(buf, 1, '<2024-01-01 Mon>'))
    end)
  end)

  describe('remove_scheduled / remove_deadline', function()
    it('removes just the SCHEDULED part, keeping DEADLINE', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon> DEADLINE: <2024-01-05 Fri>' })
      plan.remove_scheduled(buf, 1)
      assert.are.equal('DEADLINE: <2024-01-05 Fri>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('deletes the whole planning line when nothing is left', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', 'body' })
      plan.remove_scheduled(buf, 1)
      assert.are.same({ '* Task', 'body' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('is a no-op when there is no planning line', function()
      local buf = make_buf({ '* Task', 'body' })
      plan.remove_scheduled(buf, 1)
      assert.are.same({ '* Task', 'body' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)

  describe('get_scheduled / get_deadline', function()
    it('reads back a set value', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>' })
      assert.are.equal('<2024-01-01 Mon>', plan.get_scheduled(buf, 1))
      assert.is_nil(plan.get_deadline(buf, 1))
    end)

    it('returns nil when there is no planning line at all', function()
      local buf = make_buf({ '* Task', 'body' })
      assert.is_nil(plan.get_scheduled(buf, 1))
    end)
  end)

  describe('schedule_interactive / deadline_interactive', function()
    local function make_win(lines)
      local buf = make_buf(lines)
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

    it('prompts defaulting to today and sets an active SCHEDULED timestamp', function()
      local buf, win = make_win({ '* Task' })
      local prompt_opts
      vim.ui.input = function(opts, on_confirm)
        prompt_opts = opts
        on_confirm('2024-03-10')
      end
      plan.schedule_interactive(buf, win, 1)
      assert.is_not_nil(prompt_opts.default)
      assert.are.equal('SCHEDULED: <2024-03-10 Sun>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('prompts pre-filled with an existing DEADLINE for editing', function()
      local buf, win = make_win({ '* Task', 'DEADLINE: <2024-01-05 Fri>' })
      local prompt_opts
      vim.ui.input = function(opts, on_confirm)
        prompt_opts = opts
        on_confirm('2024-02-20')
      end
      plan.deadline_interactive(buf, win, 1)
      assert.are.equal('2024-01-05', prompt_opts.default)
      assert.are.equal('DEADLINE: <2024-02-20 Tue>', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2])
    end)

    it('does nothing when the prompt is cancelled', function()
      local buf, win = make_win({ '* Task' })
      vim.ui.input = function(opts, on_confirm)
        on_confirm(nil)
      end
      plan.schedule_interactive(buf, win, 1)
      assert.are.same({ '* Task' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('does nothing when lnum is not inside a headline', function()
      local buf, win = make_win({ 'no headline' })
      local called = false
      vim.ui.input = function()
        called = true
      end
      plan.schedule_interactive(buf, win, 1)
      assert.is_false(called)
    end)
  end)
end)

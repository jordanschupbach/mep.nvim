local review = require('mep.flashcards.review')
local state_mod = require('mep.flashcards.state')

local function feed(lhs)
  vim.cmd('normal ' .. vim.api.nvim_replace_termcodes(lhs, true, false, true))
end

describe('mep.flashcards.review', function()
  local card_bufnr

  local function make_entry(title, answer_lines, sm2_state)
    vim.api.nvim_buf_set_lines(card_bufnr, 0, -1, false, vim.list_extend({ '* ' .. title }, answer_lines or {}))
    return { bufnr = card_bufnr, file = 'test.org', lnum = 1, title = title, state = sm2_state or state_mod.read(card_bufnr, 1) }
  end

  before_each(function()
    card_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[card_bufnr].filetype = 'org'
  end)

  after_each(function()
    review._reset()
    if vim.api.nvim_buf_is_valid(card_bufnr) then
      vim.api.nvim_buf_delete(card_bufnr, { force = true })
    end
  end)

  describe('start', function()
    it('notifies and opens nothing for an empty entry list', function()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      review.start({})
      vim.notify = orig_notify
      assert.is_false(review.is_active())
      assert.matches('no cards due', notified)
    end)

    it('opens a window showing the first card question, unrevealed', function()
      local entry = make_entry('What is 2+2?', { '4' })
      review.start({ entry })
      assert.is_true(review.is_active())

      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('What is 2+2?', text)
      assert.is_nil(text:match('^4$'))
      assert.matches('reveal answer', text)
    end)

    it('refuses to start a second session while one is open', function()
      local entry = make_entry('Q', { 'A' })
      review.start({ entry })
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      review.start({ entry })
      vim.notify = orig_notify
      assert.matches('already open', notified)
    end)
  end)

  describe('reveal and grade', function()
    it('<CR> reveals the answer body and the grading hint', function()
      local entry = make_entry('Q', { 'The answer.' })
      review.start({ entry })
      feed('<CR>')

      local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('The answer%.', text)
      assert.matches('%[a%]gain', text)
      assert.matches('%[e%]asy', text)
    end)

    it('a grading key before reveal does nothing', function()
      local entry = make_entry('Q', { 'A' })
      review.start({ entry })
      feed('g') -- 'good' key, pressed before revealing
      -- Still on card 1/1, still unrevealed (no grading hint shown).
      local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('reveal answer', text)
    end)

    it('grading writes the new SM-2 state back to the headline', function()
      local entry = make_entry('Q', { 'A' })
      review.start({ entry })
      feed('<CR>')
      feed('g') -- good

      local new_state = state_mod.read(card_bufnr, 1)
      assert.are.equal(1, new_state.reps)
      assert.are.equal(1, new_state.interval)
      assert.is_not_nil(new_state.due)
    end)

    it('closes and notifies "review complete" after grading the last card', function()
      local entry = make_entry('Q', { 'A' })
      review.start({ entry })
      feed('<CR>')

      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      feed('g')
      vim.notify = orig_notify

      assert.is_false(review.is_active())
      assert.matches('review complete %(1 card%)', notified)
    end)

    it('advances to the next card without closing when more remain', function()
      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.bo[buf2].filetype = 'org'
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { '* Second question', 'Second answer.' })
      local entry1 = make_entry('First question', { 'First answer.' })
      local entry2 = { bufnr = buf2, file = 'test2.org', lnum = 1, title = 'Second question', state = state_mod.read(buf2, 1) }

      review.start({ entry1, entry2 })
      feed('<CR>')
      feed('g')

      assert.is_true(review.is_active())
      local win = vim.api.nvim_get_current_win()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
      assert.matches('Second question', text)
      assert.matches('Card 2/2', text)

      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)

  describe('close/quit', function()
    it('q closes the session without grading', function()
      local entry = make_entry('Q', { 'A' })
      review.start({ entry })
      feed('<CR>')
      feed('q')
      assert.is_false(review.is_active())
      -- No SM-2 state was ever written.
      local s = state_mod.read(card_bufnr, 1)
      assert.is_nil(s.due)
    end)

    it('M.close() is a no-op when nothing is active', function()
      assert.has_no.errors(function()
        review.close()
      end)
    end)
  end)
end)

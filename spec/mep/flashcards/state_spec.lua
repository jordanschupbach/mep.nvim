local state_mod = require('mep.flashcards.state')
local sm2 = require('mep.flashcards.sm2')

describe('mep.flashcards.state', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = 'org'
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('read', function()
    it('returns sm2.DEFAULT-shaped state with a nil due date for a fresh headline', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Question' })
      local s = state_mod.read(bufnr, 1)
      assert.are.equal(sm2.DEFAULT.ef, s.ef)
      assert.are.equal(sm2.DEFAULT.reps, s.reps)
      assert.are.equal(sm2.DEFAULT.interval, s.interval)
      assert.is_nil(s.due)
    end)

    it('reads back previously written state', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Question' })
      state_mod.write(bufnr, 1, { ef = 2.3, reps = 2, interval = 6, due = '2024-06-01' })
      local s = state_mod.read(bufnr, 1)
      assert.are.equal(2.3, s.ef)
      assert.are.equal(2, s.reps)
      assert.are.equal(6, s.interval)
      assert.are.equal('2024-06-01', s.due)
    end)

    it('falls back to defaults for an unparseable property value', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Question', ':PROPERTIES:', ':DRILL_EF: not-a-number', ':END:' })
      local s = state_mod.read(bufnr, 1)
      assert.are.equal(sm2.DEFAULT.ef, s.ef)
    end)
  end)

  describe('write', function()
    it('creates a properties drawer with all four keys', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Question' })
      state_mod.write(bufnr, 1, { ef = 2.6, reps = 1, interval = 1, due = '2024-01-02' })
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.matches(':DRILL_EF: 2%.60', text)
      assert.matches(':DRILL_REPS: 1', text)
      assert.matches(':DRILL_INTERVAL: 1', text)
      assert.matches(':DRILL_DUE: 2024%-01%-02', text)
    end)
  end)

  describe('is_due', function()
    it('is true for a never-reviewed card (due == nil)', function()
      assert.is_true(state_mod.is_due({ due = nil }))
    end)

    it('is true for a card due today or earlier', function()
      assert.is_true(state_mod.is_due({ due = '2024-01-01' }, '2024-01-01'))
      assert.is_true(state_mod.is_due({ due = '2023-12-31' }, '2024-01-01'))
    end)

    it('is false for a card due in the future', function()
      assert.is_false(state_mod.is_due({ due = '2024-01-02' }, '2024-01-01'))
    end)
  end)
end)

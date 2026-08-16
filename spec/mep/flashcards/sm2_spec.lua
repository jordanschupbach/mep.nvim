local sm2 = require('mep.flashcards.sm2')

describe('mep.flashcards.sm2', function()
  describe('grade', function()
    it('schedules 1 day, then 6 days, then interval*ef on consecutive "good" grades', function()
      local s1 = sm2.grade(sm2.DEFAULT, 'good')
      assert.are.equal(1, s1.interval)
      assert.are.equal(1, s1.reps)

      local s2 = sm2.grade(s1, 'good')
      assert.are.equal(6, s2.interval)
      assert.are.equal(2, s2.reps)

      local s3 = sm2.grade(s2, 'good')
      assert.are.equal(math.floor(6 * s2.ef + 0.5), s3.interval)
      assert.are.equal(3, s3.reps)
    end)

    it('resets repetitions and interval to 1 on "again"', function()
      local s1 = sm2.grade(sm2.DEFAULT, 'good')
      local s2 = sm2.grade(s1, 'good')
      local reset = sm2.grade(s2, 'again')
      assert.are.equal(0, reset.reps)
      assert.are.equal(1, reset.interval)
    end)

    it('grows the easiness factor on "easy" and shrinks it on "hard"', function()
      local easy = sm2.grade(sm2.DEFAULT, 'easy')
      local hard = sm2.grade(sm2.DEFAULT, 'hard')
      assert.is_true(easy.ef > sm2.DEFAULT.ef)
      assert.is_true(hard.ef < sm2.DEFAULT.ef)
    end)

    it('floors the easiness factor at 1.3', function()
      local state = sm2.DEFAULT
      for _ = 1, 50 do
        state = sm2.grade(state, 'again')
      end
      assert.is_true(state.ef >= 1.3)
    end)

    it('errors on an unknown grade', function()
      assert.has_error(function()
        sm2.grade(sm2.DEFAULT, 'bogus')
      end)
    end)

    it('defaults to a fresh state when state is nil', function()
      local s = sm2.grade(nil, 'good')
      assert.are.equal(1, s.interval)
    end)
  end)

  describe('due_date', function()
    it('adds state.interval days to the given date', function()
      assert.are.equal('2024-01-06', sm2.due_date({ interval = 5 }, '2024-01-01'))
    end)

    it('rolls over a month boundary', function()
      assert.are.equal('2024-02-01', sm2.due_date({ interval = 1 }, '2024-01-31'))
    end)

    it('defaults to today when no date is given', function()
      assert.are.equal(sm2.due_date({ interval = 0 }), os.date('%Y-%m-%d'))
    end)
  end)
end)

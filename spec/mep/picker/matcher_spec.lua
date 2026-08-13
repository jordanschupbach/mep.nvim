local matcher = require('mep.picker.matcher')

describe('mep.picker.matcher', function()
  describe('match', function()
    it('returns score 0 and no positions for an empty query', function()
      local score, positions = matcher.match('anything', '')
      assert.are.equal(0, score)
      assert.are.same({}, positions)
    end)

    it('matches a subsequence and returns 1-based byte positions', function()
      local score, positions = matcher.match('hello world', 'hw')
      assert.is_not_nil(score)
      assert.are.same({ 1, 7 }, positions)
    end)

    it('returns nil when the query is not a subsequence', function()
      local score = matcher.match('hello', 'xyz')
      assert.is_nil(score)
    end)

    it('is case-insensitive unless the query has an uppercase letter (smart case)', function()
      local lower_score = matcher.match('Hello World', 'hw')
      assert.is_not_nil(lower_score)

      local exact_case_score = matcher.match('Hello World', 'HW')
      assert.is_not_nil(exact_case_score)

      -- smart case: an uppercase query char must match uppercase exactly
      local mismatched_case_score = matcher.match('hello world', 'HW')
      assert.is_nil(mismatched_case_score)
    end)

    it('scores consecutive-character matches higher than scattered ones', function()
      local consecutive_score = matcher.match('picker.lua', 'pick')
      local scattered_score = matcher.match('p_i_c_k.lua', 'pick')
      assert.is_true(consecutive_score > scattered_score)
    end)

    it('scores a match at the start of the string, or after a separator, higher', function()
      local start_score = matcher.match('matcher.lua', 'match')
      local mid_score = matcher.match('xxmatch.lua', 'match')
      assert.is_true(start_score > mid_score)

      local boundary_score = matcher.match('foo_match.lua', 'match')
      local no_boundary_score = matcher.match('foomatch.lua', 'match')
      assert.is_true(boundary_score > no_boundary_score)
    end)

    it('penalizes a tighter/shorter overall string less than a longer one', function()
      local short_score = matcher.match('init.lua', 'init')
      local long_score = matcher.match('init_but_a_much_longer_filename.lua', 'init')
      assert.is_true(short_score > long_score)
    end)
  end)

  describe('filter', function()
    local function name(item)
      return item.name
    end

    it('drops non-matching items and sorts the rest best-match-first', function()
      local items = {
        { name = 'foobar.txt' },
        { name = 'init.lua' },
        { name = 'picker_init.lua' },
      }
      local results = matcher.filter(items, 'init', name)
      assert.are.equal(2, #results)
      assert.are.equal('init.lua', results[1].item.name)
      assert.are.equal('picker_init.lua', results[2].item.name)
    end)

    it('returns every item, unscored-but-present, for an empty query', function()
      local items = { { name = 'a' }, { name = 'b' } }
      local results = matcher.filter(items, '', name)
      assert.are.equal(2, #results)
    end)

    it('returns an empty list when nothing matches', function()
      local items = { { name = 'a' }, { name = 'b' } }
      local results = matcher.filter(items, 'zzz', name)
      assert.are.same({}, results)
    end)

    it('carries positions through for highlighting', function()
      local results = matcher.filter({ { name = 'init.lua' } }, 'init', name)
      assert.are.same({ 1, 2, 3, 4 }, results[1].positions)
    end)
  end)
end)

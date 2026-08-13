local tagmatch = require('mep.org.tagmatch')

describe('mep.org.tagmatch', function()
  describe('parse', function()
    it('parses a single positive term', function()
      local groups = tagmatch.parse('+work')
      assert.are.same({ { { tag = 'work', negate = false } } }, groups)
    end)

    it('parses a single negative term', function()
      local groups = tagmatch.parse('-urgent')
      assert.are.same({ { { tag = 'urgent', negate = true } } }, groups)
    end)

    it('parses an implicit AND group', function()
      local groups = tagmatch.parse('+work-urgent')
      assert.are.same({ {
        { tag = 'work', negate = false },
        { tag = 'urgent', negate = true },
      } }, groups)
    end)

    it('splits OR groups on |', function()
      local groups = tagmatch.parse('+work|+home')
      assert.are.equal(2, #groups)
      assert.are.same({ { tag = 'work', negate = false } }, groups[1])
      assert.are.same({ { tag = 'home', negate = false } }, groups[2])
    end)

    it('parses a mix of AND within OR groups', function()
      local groups = tagmatch.parse('+work+urgent|+home')
      assert.are.equal(2, #groups)
      assert.are.equal(2, #groups[1])
      assert.are.equal(1, #groups[2])
    end)

    it('allows tag names with underscores and @', function()
      local groups = tagmatch.parse('+@home_office')
      assert.are.equal('@home_office', groups[1][1].tag)
    end)

    it('returns nil for an empty expression', function()
      assert.is_nil(tagmatch.parse(''))
    end)

    it('returns nil for an expression with no valid terms', function()
      assert.is_nil(tagmatch.parse('||'))
    end)

    it('skips a malformed term with no sign but keeps valid ones around it', function()
      local groups = tagmatch.parse('+work junk-urgent')
      -- "junk" has no leading +/- so it's ignored; "-urgent" still parses
      local tags = {}
      for _, t in ipairs(groups[1]) do
        tags[#tags + 1] = t.tag
      end
      assert.are.same({ 'work', 'urgent' }, tags)
    end)
  end)

  describe('matches', function()
    it('matches a simple positive term when the tag is present', function()
      local groups = tagmatch.parse('+work')
      assert.is_true(tagmatch.matches(groups, { 'work', 'home' }))
    end)

    it('does not match when a required tag is absent', function()
      local groups = tagmatch.parse('+work')
      assert.is_false(tagmatch.matches(groups, { 'home' }))
    end)

    it('does not match when an excluded tag is present', function()
      local groups = tagmatch.parse('+work-urgent')
      assert.is_false(tagmatch.matches(groups, { 'work', 'urgent' }))
    end)

    it('matches when the excluded tag is absent', function()
      local groups = tagmatch.parse('+work-urgent')
      assert.is_true(tagmatch.matches(groups, { 'work' }))
    end)

    it('requires every AND term within one group', function()
      local groups = tagmatch.parse('+work+urgent')
      assert.is_false(tagmatch.matches(groups, { 'work' }))
      assert.is_true(tagmatch.matches(groups, { 'work', 'urgent' }))
    end)

    it('matches if any OR group is fully satisfied (AND binds tighter than OR)', function()
      local groups = tagmatch.parse('+work+urgent|+home')
      assert.is_true(tagmatch.matches(groups, { 'home' })) -- second group alone
      assert.is_false(tagmatch.matches(groups, { 'work' })) -- first group incomplete
      assert.is_true(tagmatch.matches(groups, { 'work', 'urgent' }))
    end)

    it('matches nothing against an empty tag list unless the expression is all-negative', function()
      local groups = tagmatch.parse('-urgent')
      assert.is_true(tagmatch.matches(groups, {}))
      local groups2 = tagmatch.parse('+work')
      assert.is_false(tagmatch.matches(groups2, {}))
    end)
  end)

  describe('eval', function()
    it('parses and matches in one call', function()
      assert.is_true(tagmatch.eval('+work-urgent', { 'work' }))
      assert.is_false(tagmatch.eval('+work-urgent', { 'work', 'urgent' }))
    end)

    it('returns false (not an error) for a malformed expression', function()
      assert.is_false(tagmatch.eval('', { 'work' }))
      assert.is_false(tagmatch.eval('||', { 'work' }))
    end)
  end)
end)

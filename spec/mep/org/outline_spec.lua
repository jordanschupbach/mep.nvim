local outline = require('mep.org.outline')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.outline', function()
  local SAMPLE = {
    '* Heading 1', -- 1
    'body 1', -- 2
    '** Sub 1.1', -- 3
    'sub body', -- 4
    '** Sub 1.2', -- 5
    '* Heading 2', -- 6
    'body 2', -- 7
  }

  describe('next_headline / prev_headline', function()
    it('finds the next headline after a given line', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(3, outline.next_headline(buf, 1))
      assert.are.equal(5, outline.next_headline(buf, 3))
      assert.is_nil(outline.next_headline(buf, 6))
    end)

    it('finds the previous headline before a given line', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(5, outline.prev_headline(buf, 6))
      assert.are.equal(3, outline.prev_headline(buf, 5))
      assert.is_nil(outline.prev_headline(buf, 1))
    end)

    it('respects max_level, skipping deeper headlines', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(6, outline.next_headline(buf, 1, 1)) -- skips level-2 Sub 1.1/1.2
    end)
  end)

  describe('current_headline', function()
    it('returns the line itself when it is a headline', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(3, outline.current_headline(buf, 3))
    end)

    it('returns the nearest headline above a body line', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(3, outline.current_headline(buf, 4))
    end)

    it('returns nil above any headline', function()
      local buf = make_buf({ 'no headline yet', '* first' })
      assert.is_nil(outline.current_headline(buf, 1))
    end)
  end)

  describe('parent_headline', function()
    it('returns the enclosing headline of a lower level', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(1, outline.parent_headline(buf, 3))
      assert.are.equal(1, outline.parent_headline(buf, 4))
    end)

    it('returns nil for a top-level headline', function()
      local buf = make_buf(SAMPLE)
      assert.is_nil(outline.parent_headline(buf, 1))
    end)
  end)

  describe('subtree_end', function()
    it('stops before the next headline at the same or shallower level', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(5, outline.subtree_end(buf, 1)) -- Heading 1's subtree includes Sub 1.1 and 1.2
      assert.are.equal(4, outline.subtree_end(buf, 3)) -- Sub 1.1's subtree is just its body
    end)

    it('runs to the end of the buffer for the last subtree', function()
      local buf = make_buf(SAMPLE)
      assert.are.equal(7, outline.subtree_end(buf, 6))
    end)
  end)

  describe('change_level', function()
    it('demotes (increases stars) by delta', function()
      local buf = make_buf({ '* Heading' })
      local new_level = outline.change_level(buf, 1, 1)
      assert.are.equal(2, new_level)
      assert.are.equal('** Heading', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('promotes (decreases stars) by delta', function()
      local buf = make_buf({ '*** Heading' })
      outline.change_level(buf, 1, -1)
      assert.are.equal('** Heading', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('clamps promotion at a minimum of 1 star', function()
      local buf = make_buf({ '* Heading' })
      local new_level = outline.change_level(buf, 1, -1)
      assert.are.equal(1, new_level)
      assert.are.equal('* Heading', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns nil and does nothing for a non-headline line', function()
      local buf = make_buf({ 'not a headline' })
      assert.is_nil(outline.change_level(buf, 1, 1))
      assert.are.equal('not a headline', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('change_level_subtree', function()
    it('changes every headline in the subtree, preserving relative depth', function()
      local buf = make_buf(SAMPLE)
      local new_level = outline.change_level_subtree(buf, 1, 1)
      assert.are.equal(2, new_level)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('** Heading 1', lines[1])
      assert.are.equal('*** Sub 1.1', lines[3])
      assert.are.equal('*** Sub 1.2', lines[5])
      assert.are.equal('* Heading 2', lines[6]) -- untouched, outside the subtree
    end)

    it('does not touch non-headline body lines', function()
      local buf = make_buf(SAMPLE)
      outline.change_level_subtree(buf, 1, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('body 1', lines[2])
    end)

    it('clamps so the root never drops below 1 star, scaling descendants the same amount', function()
      local buf = make_buf({ '* Root', '** Child' })
      local new_level = outline.change_level_subtree(buf, 1, -1)
      assert.are.equal(1, new_level)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('* Root', lines[1])
      assert.are.equal('** Child', lines[2]) -- delta clamped to 0, not -1
    end)

    it('returns nil for a non-headline line', function()
      local buf = make_buf({ 'not a headline' })
      assert.is_nil(outline.change_level_subtree(buf, 1, 1))
    end)
  end)

  describe('move_subtree', function()
    it('swaps with the previous sibling (direction -1)', function()
      local buf = make_buf({ '* A', '* B', '* C' })
      local new_start = outline.move_subtree(buf, 2, -1)
      assert.are.equal(1, new_start)
      assert.are.same({ '* B', '* A', '* C' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('swaps with the next sibling (direction 1)', function()
      local buf = make_buf({ '* A', '* B', '* C' })
      local new_start = outline.move_subtree(buf, 2, 1)
      assert.are.equal(3, new_start)
      assert.are.same({ '* A', '* C', '* B' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('moves the whole subtree block, not just the headline line', function()
      local buf = make_buf({ '* A', 'body a', '* B', 'body b' })
      outline.move_subtree(buf, 3, -1)
      assert.are.same({ '* B', 'body b', '* A', 'body a' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('does not cross into a parent level (no sibling beyond it)', function()
      local buf = make_buf({ '* Parent', '** Child' })
      assert.is_nil(outline.move_subtree(buf, 2, -1))
      assert.is_nil(outline.move_subtree(buf, 2, 1))
    end)

    it('returns nil when already first (direction -1) or last (direction 1)', function()
      local buf = make_buf({ '* A', '* B' })
      assert.is_nil(outline.move_subtree(buf, 1, -1))
      assert.is_nil(outline.move_subtree(buf, 2, 1))
    end)

    it('round-trips: moving down then up restores the original order', function()
      local buf = make_buf({ '* A', '* B', '* C' })
      outline.move_subtree(buf, 1, 1)
      outline.move_subtree(buf, 2, -1)
      assert.are.same({ '* A', '* B', '* C' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('returns nil for a non-headline line', function()
      local buf = make_buf({ 'not a headline' })
      assert.is_nil(outline.move_subtree(buf, 1, -1))
    end)
  end)
end)

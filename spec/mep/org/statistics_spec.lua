local statistics = require('mep.org.statistics')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.statistics', function()
  describe('find_cookie', function()
    it('finds a fraction cookie', function()
      local s, e, kind = statistics.find_cookie('Task [2/5]')
      assert.are.equal('fraction', kind)
      assert.are.equal('[2/5]', ('Task [2/5]'):sub(s, e))
    end)

    it('finds a percent cookie', function()
      local s, e, kind = statistics.find_cookie('Task [40%]')
      assert.are.equal('percent', kind)
      assert.are.equal('[40%]', ('Task [40%]'):sub(s, e))
    end)

    it('finds an empty cookie', function()
      local s, e, kind = statistics.find_cookie('Task [/]')
      assert.are.equal('fraction', kind)
      assert.are.equal('[/]', ('Task [/]'):sub(s, e))
    end)

    it('returns nil when there is no cookie', function()
      assert.is_nil(statistics.find_cookie('Plain task'))
    end)
  end)

  describe('count_checkboxes', function()
    it('counts checked and total within the subtree only', function()
      local buf = make_buf({
        '* Task [/]',
        '- [X] a',
        '- [ ] b',
        '- [X] c',
        '* Other',
        '- [ ] not counted',
      })
      local done, total = statistics.count_checkboxes(buf, 1)
      assert.are.equal(2, done)
      assert.are.equal(3, total)
    end)

    it('returns 0, 0 when there are no checkboxes', function()
      local buf = make_buf({ '* Task', 'plain body' })
      local done, total = statistics.count_checkboxes(buf, 1)
      assert.are.equal(0, done)
      assert.are.equal(0, total)
    end)
  end)

  describe('count_child_todos', function()
    it('counts only direct children, done = last todo_keywords entry', function()
      local buf = make_buf({
        '* Parent [/]',
        '** TODO Child A',
        '** DONE Child B',
        '** TODO Child C',
        '*** DONE Grandchild (not counted)',
      })
      local done, total = statistics.count_child_todos(buf, 1, { 'TODO', 'DONE' })
      assert.are.equal(1, done)
      assert.are.equal(3, total)
    end)

    it('counts a child with no keyword as not done', function()
      local buf = make_buf({
        '* Parent',
        '** No keyword child',
      })
      local done, total = statistics.count_child_todos(buf, 1, { 'TODO', 'DONE' })
      assert.are.equal(0, done)
      assert.are.equal(1, total)
    end)
  end)

  describe('update_cookie', function()
    it('prefers checkboxes over child todos when both exist', function()
      local buf = make_buf({
        '* Parent [/]',
        '- [X] a',
        '- [ ] b',
        '** TODO ignored for this cookie',
      })
      local done, total = statistics.update_cookie(buf, 1, { 'TODO', 'DONE' })
      assert.are.equal(1, done)
      assert.are.equal(2, total)
      assert.are.equal('* Parent [1/2]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('falls back to child todos when there are no checkboxes', function()
      local buf = make_buf({
        '* Parent [/]',
        '** TODO A',
        '** DONE B',
      })
      statistics.update_cookie(buf, 1, { 'TODO', 'DONE' })
      assert.are.equal('* Parent [1/2]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('renders a percent cookie', function()
      local buf = make_buf({
        '* Parent [%]',
        '- [X] a',
        '- [ ] b',
        '- [ ] c',
        '- [ ] d',
      })
      statistics.update_cookie(buf, 1, {})
      assert.are.equal('* Parent [25%]', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('is a no-op when the headline has no cookie', function()
      local buf = make_buf({ '* Parent', '- [X] a' })
      assert.is_nil(statistics.update_cookie(buf, 1, {}))
      assert.are.equal('* Parent', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)
  end)

  describe('update_ancestors', function()
    it('updates every ancestor cookie up the tree, not just the immediate parent', function()
      local buf = make_buf({
        '* Grandparent [/]',
        '** Parent [/]',
        '*** TODO Child',
      })
      statistics.update_ancestors(buf, 3, { 'TODO', 'DONE' })
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Parent's cookie: 1 direct child (Child, TODO not DONE) -> [0/1].
      -- Grandparent's cookie: also falls back to *its* direct child count
      -- (just "Parent", which carries no TODO keyword of its own) -> [0/1]
      -- too, via a completely different count than Parent's.
      assert.are.equal('** Parent [0/1]', lines[2])
      assert.are.equal('* Grandparent [0/1]', lines[1])
    end)

    it('propagates a checkbox toggle up through multiple cookie-bearing ancestors', function()
      local buf = make_buf({
        '* Grandparent [/]',
        '** Parent [/]',
        '- [ ] leaf',
      })
      statistics.update_ancestors(buf, 3, {})
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('** Parent [0/1]', lines[2])
      assert.are.equal('* Grandparent [0/1]', lines[1])
    end)
  end)
end)

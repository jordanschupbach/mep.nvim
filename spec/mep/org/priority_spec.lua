local priority = require('mep.org.priority')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.priority', function()
  describe('set', function()
    it('adds a priority cookie to a headline with none', function()
      local buf = make_buf({ '* Plain task' })
      local result = priority.set(buf, 1, 'A')
      assert.are.equal('A', result)
      assert.are.equal('* [#A] Plain task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('replaces an existing priority cookie', function()
      local buf = make_buf({ '* [#A] Task' })
      priority.set(buf, 1, 'C')
      assert.are.equal('* [#C] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('clears the cookie when priority is nil', function()
      local buf = make_buf({ '* [#A] Task' })
      priority.set(buf, 1, nil)
      assert.are.equal('* Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('preserves the TODO keyword', function()
      local buf = make_buf({ '* TODO Task' })
      priority.set(buf, 1, 'B', { 'TODO', 'DONE' })
      assert.are.equal('* TODO [#B] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('operates on the enclosing headline, not just an exact headline line', function()
      local buf = make_buf({ '* Task', 'body text' })
      priority.set(buf, 2, 'A')
      assert.are.equal('* [#A] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(priority.set(buf, 1, 'A'))
    end)
  end)

  describe('cycle', function()
    it('cycles through the default A -> B -> C -> none -> A sequence', function()
      local buf = make_buf({ '* Task' })
      assert.are.equal('A', priority.cycle(buf, 1))
      assert.are.equal('B', priority.cycle(buf, 1))
      assert.are.equal('C', priority.cycle(buf, 1))
      assert.is_nil(priority.cycle(buf, 1))
      assert.are.equal('A', priority.cycle(buf, 1))
    end)

    it('rewrites the line at each step', function()
      local buf = make_buf({ '* Task' })
      priority.cycle(buf, 1)
      assert.are.equal('* [#A] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      priority.cycle(buf, 1)
      assert.are.equal('* [#B] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('honors a custom priorities list', function()
      -- priority cookies are always a single character (matching real
      -- org-mode and mep.org.headline's own [#X] parsing), so a custom
      -- list must use single-character entries too
      local buf = make_buf({ '* Task' })
      assert.are.equal('1', priority.cycle(buf, 1, { '1', '2' }))
      assert.are.equal('2', priority.cycle(buf, 1, { '1', '2' }))
      assert.is_nil(priority.cycle(buf, 1, { '1', '2' }))
    end)

    it('preserves the TODO keyword while cycling', function()
      local buf = make_buf({ '* TODO Task' })
      priority.cycle(buf, 1, nil, { 'TODO', 'DONE' })
      assert.are.equal('* TODO [#A] Task', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(priority.cycle(buf, 1))
    end)
  end)
end)

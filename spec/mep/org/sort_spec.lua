local sort = require('mep.org.sort')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.sort', function()
  describe('criteria.alpha', function()
    it('sorts top-level siblings alphabetically, case-insensitively', function()
      local buf = make_buf({ '* charlie', '* Alpha', '* bravo' })
      sort.sort_siblings(buf, 1, 'alpha', {})
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* Alpha', '* bravo', '* charlie' }, lines)
    end)

    it('reverses when reverse = true', function()
      local buf = make_buf({ '* a', '* c', '* b' })
      sort.sort_siblings(buf, 1, 'alpha', {}, true)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* c', '* b', '* a' }, lines)
    end)
  end)

  describe('criteria.todo', function()
    it('orders by position in todo_keywords, no-keyword last', function()
      local buf = make_buf({ '* DONE c', '* TODO a', '* b' })
      sort.sort_siblings(buf, 1, 'todo', { 'TODO', 'DONE' })
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* TODO a', '* DONE c', '* b' }, lines)
    end)
  end)

  describe('criteria.priority', function()
    it('orders A before B before C, no-priority last', function()
      local buf = make_buf({ '* [#C] c', '* [#A] a', '* b', '* [#B] b2' })
      sort.sort_siblings(buf, 1, 'priority', {})
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* [#A] a', '* [#B] b2', '* [#C] c', '* b' }, lines)
    end)
  end)

  describe('subtree scoping', function()
    it('moves whole subtrees together, not just headline lines', function()
      local buf = make_buf({
        '* b',
        'body of b',
        '* a',
        'body of a',
      })
      sort.sort_siblings(buf, 1, 'alpha', {})
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* a', 'body of a', '* b', 'body of b' }, lines)
    end)

    it('only reorders siblings under the same parent, leaving ancestors and their own siblings untouched', function()
      local buf = make_buf({
        '* Top Z',
        '** child b',
        '** child a',
        '* Top A',
      })
      sort.sort_siblings(buf, 2, 'alpha', {})
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ '* Top Z', '** child a', '** child b', '* Top A' }, lines)
    end)
  end)

  it('returns nil when lnum is not inside a headline', function()
    local buf = make_buf({ 'no headline' })
    assert.is_nil(sort.sort_siblings(buf, 1, 'alpha', {}))
  end)

  it('is a no-op with a single sibling', function()
    local buf = make_buf({ '* only' })
    local n = sort.sort_siblings(buf, 1, 'alpha', {})
    assert.are.equal(1, n)
    assert.are.same({ '* only' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it('raises for an unknown criteria key', function()
    local buf = make_buf({ '* a' })
    assert.has_error(function()
      sort.sort_siblings(buf, 1, 'bogus', {})
    end)
  end)
end)

local todo = require('mep.org.todo')

local KEYWORDS = { 'TODO', 'DONE' }

local function make_buf(line)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  return buf
end

describe('mep.org.todo', function()
  it('sets the first keyword on a headline with no TODO state', function()
    local buf = make_buf('* Buy milk')
    local new_state = todo.cycle(buf, 1, KEYWORDS)
    assert.are.equal('TODO', new_state)
    assert.are.equal('* TODO Buy milk', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it('advances to the next keyword', function()
    local buf = make_buf('* TODO Buy milk')
    local new_state = todo.cycle(buf, 1, KEYWORDS)
    assert.are.equal('DONE', new_state)
    assert.are.equal('* DONE Buy milk', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it('cycles past the last keyword to no keyword at all', function()
    local buf = make_buf('* DONE Buy milk')
    local new_state = todo.cycle(buf, 1, KEYWORDS)
    assert.is_nil(new_state)
    assert.are.equal('* Buy milk', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it('preserves tags through a cycle', function()
    local buf = make_buf('* Buy milk :shopping:')
    todo.cycle(buf, 1, KEYWORDS)
    assert.are.equal('* TODO Buy milk  :shopping:', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it('returns nil and does nothing for a non-headline line', function()
    local buf = make_buf('not a headline')
    assert.is_nil(todo.cycle(buf, 1, KEYWORDS))
    assert.are.equal('not a headline', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)
end)

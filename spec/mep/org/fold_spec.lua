-- foldexpr() reads the queried line via vim.v.lnum + vim.fn.getline (the
-- 'foldexpr' contract), both of which operate on the *current* buffer —
-- so these tests make their buffer current rather than passing it as an
-- argument.
local fold = require('mep.org.fold')

local function set_current(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function foldlevel_at(lnum)
  vim.v.lnum = lnum
  return fold.foldexpr()
end

describe('mep.org.fold', function()
  local SAMPLE = {
    '* Heading 1', -- 1
    'body 1', -- 2
    '** Sub 1.1', -- 3
    'sub body', -- 4
    '* Heading 2', -- 5
    'body 2', -- 6
  }

  it('starts a new fold at a headline\'s own star depth', function()
    set_current(SAMPLE)
    assert.are.equal('>1', foldlevel_at(1))
    assert.are.equal('>2', foldlevel_at(3))
    assert.are.equal('>1', foldlevel_at(5))
  end)

  it('gives a non-headline line the depth of its nearest enclosing headline', function()
    set_current(SAMPLE)
    assert.are.equal(1, foldlevel_at(2))
    assert.are.equal(2, foldlevel_at(4))
    assert.are.equal(1, foldlevel_at(6))
  end)

  it('returns 0 for lines above any headline', function()
    set_current({ 'preamble', 'more preamble', '* first headline' })
    assert.are.equal(0, foldlevel_at(1))
    assert.are.equal(0, foldlevel_at(2))
  end)

  it('starts a fresh fold for each of two consecutive same-level headlines', function()
    set_current({ '* One', '* Two' })
    assert.are.equal('>1', foldlevel_at(1))
    assert.are.equal('>1', foldlevel_at(2))
  end)
end)

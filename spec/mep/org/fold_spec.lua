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

  describe('src blocks', function()
    local BLOCK_SAMPLE = {
      '* Heading', -- 1
      'intro text', -- 2
      '#+begin_src lua', -- 3
      'print(1)', -- 4
      '#+end_src', -- 5
      'outro text', -- 6
    }

    it('nests a block one level deeper than its enclosing headline', function()
      set_current(BLOCK_SAMPLE)
      assert.are.equal('>2', foldlevel_at(3)) -- #+begin_src starts the nested fold
      assert.are.equal(2, foldlevel_at(4)) -- body
      assert.are.equal(2, foldlevel_at(5)) -- #+end_src
    end)

    it('leaves surrounding prose at the headline\'s own depth', function()
      set_current(BLOCK_SAMPLE)
      assert.are.equal(1, foldlevel_at(2))
      assert.are.equal(1, foldlevel_at(6))
    end)

    it('nests a top-level block (no enclosing headline) at level 1', function()
      set_current({ '#+begin_src lua', 'print(1)', '#+end_src' })
      assert.are.equal('>1', foldlevel_at(1))
      assert.are.equal(1, foldlevel_at(2))
      assert.are.equal(1, foldlevel_at(3))
    end)

    it('pulls a directly preceding comment line into the same fold', function()
      set_current({
        '* Heading', -- 1
        '# explains the block below', -- 2
        '#+begin_src lua', -- 3
        'print(1)', -- 4
        '#+end_src', -- 5
      })
      assert.are.equal('>2', foldlevel_at(2)) -- the comment starts the fold now
      assert.are.equal(2, foldlevel_at(3))
      assert.are.equal(2, foldlevel_at(5))
    end)

    it('pulls multiple contiguous preceding comment lines into the fold', function()
      set_current({
        '# first comment line', -- 1
        '# second comment line', -- 2
        '#+begin_src lua', -- 3
        'print(1)', -- 4
        '#+end_src', -- 5
      })
      assert.are.equal('>1', foldlevel_at(1))
      assert.are.equal(1, foldlevel_at(2))
      assert.are.equal(1, foldlevel_at(3))
    end)

    it('does not pull in a comment separated from the block by a blank line', function()
      set_current({
        '# unrelated comment', -- 1
        '', -- 2
        '#+begin_src lua', -- 3
        'print(1)', -- 4
        '#+end_src', -- 5
      })
      assert.are.equal(0, foldlevel_at(1)) -- not part of the block's fold
      assert.are.equal('>1', foldlevel_at(3))
    end)

    it('does not pull in a #+ directive line (only plain # comments)', function()
      set_current({
        '#+name: not a plain comment',
        '#+begin_src lua',
        'print(1)',
        '#+end_src',
      })
      assert.are.equal(0, foldlevel_at(1))
      assert.are.equal('>1', foldlevel_at(2))
    end)

    it('handles two consecutive blocks under the same headline independently', function()
      set_current({
        '* Heading', -- 1
        '#+begin_src lua', -- 2
        'a', -- 3
        '#+end_src', -- 4
        '#+begin_src python', -- 5
        'b', -- 6
        '#+end_src', -- 7
      })
      assert.are.equal('>2', foldlevel_at(2))
      assert.are.equal('>2', foldlevel_at(5))
    end)
  end)
end)

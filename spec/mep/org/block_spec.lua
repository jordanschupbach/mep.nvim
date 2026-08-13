local block = require('mep.org.block')

describe('mep.org.block', function()
  describe('find_blocks', function()
    it('finds a quote block', function()
      local lines = { 'text', '#+BEGIN_QUOTE', 'quoted line', '#+END_QUOTE', 'more text' }
      local blocks = block.find_blocks(lines)
      assert.are.equal(1, #blocks)
      assert.are.equal('quote', blocks[1].kind)
      assert.are.equal(2, blocks[1].start_lnum)
      assert.are.equal(4, blocks[1].end_lnum)
      assert.are.same({ 'quoted line' }, blocks[1].body)
    end)

    it('is case-insensitive on both BEGIN and END', function()
      local lines = { '#+begin_verse', 'a line', '#+End_Verse' }
      local blocks = block.find_blocks(lines)
      assert.are.equal(1, #blocks)
      assert.are.equal('verse', blocks[1].kind)
    end)

    it('captures trailing args on the BEGIN line', function()
      local lines = { '#+BEGIN_EXAMPLE -n', 'code', '#+END_EXAMPLE' }
      local blocks = block.find_blocks(lines)
      assert.are.equal('-n', blocks[1].args)
    end)

    it('finds multiple distinct blocks', function()
      local lines = { '#+BEGIN_CENTER', 'x', '#+END_CENTER', '', '#+BEGIN_QUOTE', 'y', '#+END_QUOTE' }
      local blocks = block.find_blocks(lines)
      assert.are.equal(2, #blocks)
      assert.are.equal('center', blocks[1].kind)
      assert.are.equal('quote', blocks[2].kind)
    end)

    it('skips a block with mismatched kind on END', function()
      local lines = { '#+BEGIN_QUOTE', 'x', '#+END_VERSE' }
      assert.are.same({}, block.find_blocks(lines))
    end)

    it('skips an unterminated block', function()
      local lines = { '#+BEGIN_QUOTE', 'x' }
      assert.are.same({}, block.find_blocks(lines))
    end)

    it('returns an empty list when there are no blocks', function()
      assert.are.same({}, block.find_blocks({ 'just', 'plain', 'text' }))
    end)
  end)

  describe('at', function()
    it('finds the block containing a given line, inclusive of delimiters', function()
      local lines = { 'a', '#+BEGIN_QUOTE', 'b', '#+END_QUOTE', 'c' }
      assert.is_not_nil(block.at(lines, 2))
      assert.is_not_nil(block.at(lines, 3))
      assert.is_not_nil(block.at(lines, 4))
      assert.is_nil(block.at(lines, 1))
      assert.is_nil(block.at(lines, 5))
    end)
  end)
end)

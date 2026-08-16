local labels = require('mep.hints.labels')

describe('mep.hints.labels', function()
  describe('chars', function()
    it('splits an ASCII charset into individual characters', function()
      assert.are.same({ 'a', 'b', 'c' }, labels.chars('abc'))
    end)

    it('is UTF-8 aware, not byte-indexed', function()
      -- 'é' is 2 bytes in UTF-8; splitting on bytes would misalign this.
      assert.are.same({ 'é', 'a' }, labels.chars('éa'))
    end)
  end)

  describe('assign', function()
    it('assigns single-character labels when count fits the charset', function()
      local result = labels.assign(3, 'abcdef')
      assert.are.same({ 'a', 'b', 'c' }, result)
    end)

    it('assigns exactly one label per target, in charset order', function()
      local result = labels.assign(6, 'abcdef')
      assert.are.same({ 'a', 'b', 'c', 'd', 'e', 'f' }, result)
    end)

    it('falls back to two-character combinations once count exceeds the charset', function()
      local result = labels.assign(4, 'ab')
      assert.are.equal(4, #result)
      for _, label in ipairs(result) do
        assert.are.equal(2, #label)
      end
      assert.are.same({ 'aa', 'ab', 'ba', 'bb' }, result)
    end)

    it('never mixes single- and two-character labels', function()
      local result = labels.assign(3, 'ab')
      local lengths = {}
      for _, label in ipairs(result) do
        lengths[#label] = true
      end
      assert.are.equal(1, vim.tbl_count(lengths))
    end)

    it('produces unique labels', function()
      local result = labels.assign(10, 'abcdefghij')
      local seen = {}
      for _, label in ipairs(result) do
        assert.is_nil(seen[label])
        seen[label] = true
      end
    end)

    it('returns a short list rather than erroring when count exceeds capacity', function()
      local result = labels.assign(100, 'ab')
      assert.are.equal(4, #result) -- #charset^2 == 4, the max two-char labels can cover
    end)
  end)
end)

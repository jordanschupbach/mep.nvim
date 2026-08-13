local parsers = require('mep.treesitter.parsers')

describe('mep.treesitter.parsers', function()
  it('has a non-trivial curated set', function()
    local count = 0
    for _ in pairs(parsers.registry) do
      count = count + 1
    end
    assert.is_true(count >= 20)
  end)

  it('every entry has a github url and at least one .c source file', function()
    for name, entry in pairs(parsers.registry) do
      assert.is_true(entry.url:match('^https://github%.com/') ~= nil, 'bad url for ' .. name)
      assert.is_true(#entry.files > 0, 'no files for ' .. name)
      for _, f in ipairs(entry.files) do
        assert.is_true(f:match('%.c$') ~= nil, 'non-.c source for ' .. name .. ': ' .. f)
      end
    end
  end)

  it('includes common everyday languages', function()
    for _, name in ipairs({ 'lua', 'python', 'javascript', 'json', 'bash', 'markdown' }) do
      assert.is_not_nil(parsers.registry[name], name .. ' missing from curated registry')
    end
  end)

  describe('names', function()
    it('returns exactly the registry keys, sorted', function()
      local names = parsers.names()
      local expected = {}
      for name in pairs(parsers.registry) do
        expected[#expected + 1] = name
      end
      table.sort(expected)
      assert.are.same(expected, names)
    end)
  end)
end)

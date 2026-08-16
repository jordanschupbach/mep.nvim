local list = require('mep.snippet.langs.python')

describe('mep.snippet.langs.python', function()
  it('has at least 5 well-formed snippets', function()
    assert.is_true(#list >= 5)
    for _, snip in ipairs(list) do
      assert.is_true(#snip.trigger > 0)
      assert.is_true(#snip.body > 0)
    end
  end)

  it('has unique triggers', function()
    local seen = {}
    for _, snip in ipairs(list) do
      assert.is_nil(seen[snip.trigger])
      seen[snip.trigger] = true
    end
  end)

  it('includes a def snippet', function()
    local found = false
    for _, snip in ipairs(list) do
      if snip.trigger == 'def' then
        found = true
        assert.matches('^def ', snip.body)
      end
    end
    assert.is_true(found)
  end)
end)

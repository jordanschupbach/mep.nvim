local descriptions = require('mep.help.descriptions')

describe('mep.help.descriptions', function()
  it('has a desc and tag for every entry', function()
    for name, entry in pairs(descriptions.registry) do
      assert.is_string(entry.desc, name)
      assert.is_true(#entry.desc > 0, name)
      assert.are.equal('mep-' .. name, entry.tag, name)
    end
  end)

  it('includes core libraries', function()
    for _, name in ipairs({ 'core', 'picker', 'org', 'lsp', 'hints', 'dap', 'docs', 'flashcards' }) do
      assert.is_not_nil(descriptions.registry[name], name)
    end
  end)
end)

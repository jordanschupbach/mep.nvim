local registry = require('mep.repl.registry')

describe('mep.repl.registry', function()
  it('every entry is a non-empty argv list', function()
    for filetype, cmd in pairs(registry.commands) do
      assert.is_table(cmd, filetype)
      assert.is_true(#cmd > 0, filetype)
      for _, arg in ipairs(cmd) do
        assert.is_string(arg, filetype)
      end
    end
  end)

  it('includes common languages with a well-known standard REPL', function()
    assert.are.same({ 'python3' }, registry.commands.python)
    assert.are.same({ 'lua' }, registry.commands.lua)
    assert.are.same({ 'node' }, registry.commands.javascript)
    assert.are.same({ 'irb' }, registry.commands.ruby)
  end)

  it('does not include a language mep.org.babel supports but has no standard REPL', function()
    assert.is_nil(registry.commands.go)
    assert.is_nil(registry.commands.rust)
    assert.is_nil(registry.commands.c)
  end)
end)

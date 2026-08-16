local names = require('mep.colorizer.names')

describe('mep.colorizer.names', function()
  it('every value is a lower-case #rrggbb hex string', function()
    for name, hex in pairs(names.registry) do
      assert.matches('^#%x%x%x%x%x%x$', hex, name)
      assert.are.equal(hex, hex:lower(), name)
    end
  end)

  it('includes well-known basic colors with their exact standard values', function()
    assert.are.equal('#ff0000', names.registry.red)
    assert.are.equal('#00ff00', names.registry.lime)
    assert.are.equal('#008000', names.registry.green)
    assert.are.equal('#0000ff', names.registry.blue)
    assert.are.equal('#000000', names.registry.black)
    assert.are.equal('#ffffff', names.registry.white)
  end)

  it('includes CSS4-added rebeccapurple', function()
    assert.are.equal('#663399', names.registry.rebeccapurple)
  end)

  it('has a sizable registry (the full CSS named-color list)', function()
    local count = 0
    for _ in pairs(names.registry) do
      count = count + 1
    end
    assert.is_true(count > 100)
  end)
end)

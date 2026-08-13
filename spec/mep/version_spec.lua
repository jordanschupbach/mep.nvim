local version = require('mep.version')

describe('mep.version', function()
  it('is the single source of truth: a plain major/minor/patch table', function()
    assert.is_number(version.major)
    assert.is_number(version.minor)
    assert.is_number(version.patch)
  end)

  it('is reachable from the top-level module too', function()
    assert.are.equal(version, require('mep').version)
  end)
end)

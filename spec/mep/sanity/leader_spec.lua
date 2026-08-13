local leader = require('mep.sanity.leader')

describe('mep.sanity.leader', function()
  local saved_leader, saved_localleader

  before_each(function()
    saved_leader = vim.g.mapleader
    saved_localleader = vim.g.maplocalleader
  end)

  after_each(function()
    vim.g.mapleader = saved_leader
    vim.g.maplocalleader = saved_localleader
  end)

  it('sets mapleader and maplocalleader to the given key', function()
    leader.apply(' ')
    assert.are.equal(' ', vim.g.mapleader)
    assert.are.equal(' ', vim.g.maplocalleader)
  end)

  it('accepts a non-default key', function()
    leader.apply(',')
    assert.are.equal(',', vim.g.mapleader)
    assert.are.equal(',', vim.g.maplocalleader)
  end)

  it('leaves mapleader untouched when passed false', function()
    vim.g.mapleader = 'sentinel'
    leader.apply(false)
    assert.are.equal('sentinel', vim.g.mapleader)
  end)

  it('leaves mapleader untouched when passed nil', function()
    vim.g.mapleader = 'sentinel'
    leader.apply(nil)
    assert.are.equal('sentinel', vim.g.mapleader)
  end)
end)

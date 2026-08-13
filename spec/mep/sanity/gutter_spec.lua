local gutter = require('mep.sanity.gutter')

describe('mep.sanity.gutter', function()
  local saved_number, saved_signcolumn

  before_each(function()
    saved_number = vim.o.number
    saved_signcolumn = vim.o.signcolumn
  end)

  after_each(function()
    vim.o.number = saved_number
    vim.o.signcolumn = saved_signcolumn
  end)

  it('turns number on', function()
    vim.o.number = false
    gutter.apply({ number = true })
    assert.is_true(vim.o.number)
  end)

  it('sets signcolumn to "yes"', function()
    vim.o.signcolumn = 'auto'
    gutter.apply({ signcolumn = true })
    assert.are.equal('yes', vim.o.signcolumn)
  end)

  it('leaves number untouched when false', function()
    vim.o.number = false
    gutter.apply({ number = false })
    assert.is_false(vim.o.number)
  end)

  it('leaves signcolumn untouched when false', function()
    vim.o.signcolumn = 'auto'
    gutter.apply({ signcolumn = false })
    assert.are.equal('auto', vim.o.signcolumn)
  end)

  it('does nothing when passed an empty table or nil', function()
    vim.o.number, vim.o.signcolumn = false, 'auto'
    gutter.apply({})
    assert.is_false(vim.o.number)
    assert.are.equal('auto', vim.o.signcolumn)
    assert.has_no.errors(function()
      gutter.apply(nil)
    end)
  end)
end)

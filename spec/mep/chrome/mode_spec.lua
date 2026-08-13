local mode = require('mep.chrome.mode')

describe('mep.chrome.mode', function()
  local orig_mode

  before_each(function()
    orig_mode = vim.fn.mode
  end)

  after_each(function()
    vim.fn.mode = orig_mode
  end)

  local function stub(code)
    vim.fn.mode = function(full)
      assert.is_true(full == 1 or full == true)
      return code
    end
  end

  it('names plain Normal mode', function()
    stub('n')
    assert.are.equal('Normal', mode.name())
  end)

  it('names operator-pending as Normal (a prefix match, not exact)', function()
    stub('no')
    assert.are.equal('Normal', mode.name())
    stub('noV')
    assert.are.equal('Normal', mode.name())
  end)

  it('distinguishes Normal-in-terminal from plain Normal', function()
    stub('nt')
    assert.are.equal('Normal (Terminal)', mode.name())
    stub('ntT')
    assert.are.equal('Normal (Terminal)', mode.name())
  end)

  it('names Insert mode and its completion variants', function()
    stub('i')
    assert.are.equal('Insert', mode.name())
    stub('ic')
    assert.are.equal('Insert', mode.name())
  end)

  it('names every Visual variant Visual', function()
    stub('v')
    assert.are.equal('Visual', mode.name())
    stub('V')
    assert.are.equal('Visual', mode.name())
    stub('\22')
    assert.are.equal('Visual', mode.name())
  end)

  it('names Terminal mode', function()
    stub('t')
    assert.are.equal('Terminal', mode.name())
  end)

  it('names Replace mode', function()
    stub('R')
    assert.are.equal('Replace', mode.name())
  end)

  it('names Command-line mode', function()
    stub('c')
    assert.are.equal('Command', mode.name())
  end)

  it('falls back to the raw code for anything unrecognized', function()
    stub('???')
    assert.are.equal('???', mode.name())
  end)

  it('reflects the real current mode when unstubbed', function()
    assert.are.equal('Normal', mode.name())
  end)
end)

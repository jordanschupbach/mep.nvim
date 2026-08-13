local chrome = require('mep.chrome')
local config = require('mep.chrome.config')

describe('mep.chrome', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    chrome._reset()
    config.options = saved_options
  end)

  it('exposes each submodule', function()
    assert.are.equal(require('mep.chrome.click'), chrome.click)
    assert.are.equal(require('mep.chrome.hover'), chrome.hover)
    assert.are.equal(require('mep.chrome.render'), chrome.render)
    assert.are.equal(require('mep.chrome.mode'), chrome.mode)
    assert.are.equal(require('mep.chrome.statusline'), chrome.statusline)
    assert.are.equal(require('mep.chrome.winbar'), chrome.winbar)
    assert.are.equal(require('mep.chrome.tabline'), chrome.tabline)
    assert.are.equal(require('mep.chrome.statuscolumn'), chrome.statuscolumn)
    assert.are.equal(require('mep.chrome.border'), chrome.border)
  end)

  it('setup() enables only the targets whose enable=true', function()
    chrome.setup({ statusline = { enable = true }, winbar = { enable = false } })
    assert.are_not.equal('', vim.o.statusline)
    assert.are.equal("%{%v:lua.require'mep.chrome.statusline'.eval()%}", vim.o.statusline)
    assert.are_not.equal("%{%v:lua.require'mep.chrome.winbar'.eval()%}", vim.o.winbar)
  end)

  it('setup() enables border by default', function()
    local win = vim.api.nvim_get_current_win()
    chrome.setup({})
    assert.is_not_nil(vim.api.nvim_get_option_value('winhighlight', { win = win }):match('MepChromeBorderActive'))
  end)

  it('setup() with border.enable=false disables it', function()
    chrome.setup({ border = { enable = false } })
    local win = vim.api.nvim_get_current_win()
    assert.are.equal('', vim.api.nvim_get_option_value('winhighlight', { win = win }))
  end)

  it('setup() installs the click dispatch global regardless of which targets are enabled', function()
    chrome.setup({})
    assert.are.equal(require('mep.chrome.click').dispatch, _G.MepChromeClickDispatch)
  end)

  it('setup() enables hover only when statusline or winbar is enabled', function()
    chrome.setup({ statusline = { enable = false } })
    assert.is_false(vim.o.mousemoveevent)

    chrome.setup({ winbar = { enable = true } })
    assert.is_true(vim.o.mousemoveevent)
  end)

  it('setup() enables hover by default, since statusline is on by default', function()
    chrome.setup({})
    assert.is_true(vim.o.mousemoveevent)
  end)

  it('_reset() disables every target and clears the click/hover state', function()
    chrome.setup({ statusline = { enable = true }, winbar = { enable = true }, tabline = { enable = true }, statuscolumn = { enable = true } })
    chrome._reset()

    assert.is_nil(_G.MepChromeClickDispatch)
    assert.is_false(vim.o.mousemoveevent)
    assert.are_not.equal("%{%v:lua.require'mep.chrome.statusline'.eval()%}", vim.o.statusline)
    assert.are_not.equal("%{%v:lua.require'mep.chrome.winbar'.eval()%}", vim.o.winbar)
    assert.are_not.equal("%{%v:lua.require'mep.chrome.tabline'.eval()%}", vim.o.tabline)
    assert.are_not.equal("%{%v:lua.require'mep.chrome.statuscolumn'.eval()%}", vim.o.statuscolumn)
  end)
end)

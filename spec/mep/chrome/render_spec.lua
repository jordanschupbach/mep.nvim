local render = require('mep.chrome.render')
local click = require('mep.chrome.click')

describe('mep.chrome.render', function()
  after_each(function()
    click._reset()
  end)

  it('renders a plain string widget as escaped text', function()
    local text, ranges = render.render({ { text = '100%' } }, {})
    assert.are.equal('100%%', text)
    assert.are.equal(1, #ranges)
    assert.are.equal(0, ranges[1].start_col)
    assert.are.equal(4, ranges[1].end_col) -- display width of '100%', not the escaped text
  end)

  it('resolves a function text against ctx', function()
    local ctx = { active = true }
    local text = render.render({
      { text = function(c) return c.active and 'ACTIVE' or 'inactive' end },
    }, ctx)
    assert.are.equal('ACTIVE', text)
  end)

  it('wraps a widget with hl in %#...# markup, reset after', function()
    local text = render.render({ { text = 'x', hl = 'ErrorMsg' } }, {})
    assert.are.equal('%#ErrorMsg#x%#MepChromeNormal#', text)
  end)

  it('wraps an on_click widget in a %@ click region using a registered id', function()
    local widget = { text = 'go', on_click = function() end }
    local text = render.render({ widget }, {})
    local id = click.register(widget) -- same widget -> same id, already registered by render
    assert.are.equal('%' .. id .. '@v:lua.MepChromeClickDispatch@go%X', text)
  end)

  it('passes a literal %= through untouched', function()
    local text = render.render({ { text = 'a' }, '%=', { text = 'b' } }, {})
    assert.are.equal('a%=b', text)
  end)

  it('computes left-zone ranges as a running total before %=', function()
    local _, ranges = render.render({ { text = 'ab' }, { text = 'cde' } }, {})
    assert.are.same({ start_col = 0, end_col = 2 }, { start_col = ranges[1].start_col, end_col = ranges[1].end_col })
    assert.are.same({ start_col = 2, end_col = 5 }, { start_col = ranges[2].start_col, end_col = ranges[2].end_col })
  end)

  it('computes right-zone ranges against the window width', function()
    vim.cmd('vsplit')
    local win = vim.api.nvim_get_current_win()
    local width = vim.api.nvim_win_get_width(win)
    local _, ranges = render.render({ '%=', { text = 'ab' }, { text = 'c' } }, { win = win })
    assert.are.equal(width - 3, ranges[1].start_col)
    assert.are.equal(width - 1, ranges[1].end_col)
    assert.are.equal(width - 1, ranges[2].start_col)
    assert.are.equal(width, ranges[2].end_col)
    vim.cmd('close')
  end)

  it('associates each range with its own widget table', function()
    local w1, w2 = { text = 'a' }, { text = 'b' }
    local _, ranges = render.render({ w1, w2 }, {})
    assert.are.equal(w1, ranges[1].widget)
    assert.are.equal(w2, ranges[2].widget)
  end)
end)

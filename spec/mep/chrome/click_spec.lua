local click = require('mep.chrome.click')

describe('mep.chrome.click', function()
  after_each(function()
    click._reset()
  end)

  it('register() hands out a stable id per widget identity', function()
    local widget = { on_click = function() end }
    local id1 = click.register(widget)
    local id2 = click.register(widget)
    assert.are.equal(id1, id2)
  end)

  it('register() hands out distinct ids for distinct widgets', function()
    local a = { on_click = function() end }
    local b = { on_click = function() end }
    assert.are_not.equal(click.register(a), click.register(b))
  end)

  it('enable() installs _G.MepChromeClickDispatch', function()
    click.enable()
    assert.are.equal(click.dispatch, _G.MepChromeClickDispatch)
  end)

  it('disable() removes the global', function()
    click.enable()
    click.disable()
    assert.is_nil(_G.MepChromeClickDispatch)
  end)

  it('dispatch() calls the registered widget\'s on_click with a resolved ctx', function()
    local seen
    local widget = {
      on_click = function(ctx, clicks, button, mods)
        seen = { ctx = ctx, clicks = clicks, button = button, mods = mods }
      end,
    }
    local id = click.register(widget)
    click.dispatch(id, 2, 'l', 'c')

    assert.is_not_nil(seen)
    assert.are.equal(2, seen.clicks)
    assert.are.equal('l', seen.button)
    assert.are.equal('c', seen.mods)
    assert.are.equal(vim.api.nvim_get_current_win(), seen.ctx.win)
    assert.are.equal(vim.api.nvim_get_current_buf(), seen.ctx.bufnr)
    assert.is_true(seen.ctx.active)
  end)

  it('dispatch() is a no-op for an unknown minwid', function()
    assert.has_no.errors(function()
      click.dispatch(99999, 1, 'l', '')
    end)
  end)

  it('dispatch() is a no-op for a widget without on_click', function()
    local widget = {}
    local id = click.register(widget)
    assert.has_no.errors(function()
      click.dispatch(id, 1, 'l', '')
    end)
  end)

  it('_reset() clears the registry so a stale id no longer resolves', function()
    local called = false
    local widget = { on_click = function() called = true end }
    local id = click.register(widget)
    click._reset()
    click.dispatch(id, 1, 'l', '')
    assert.is_false(called)
  end)
end)

local config = require('mep.chrome.config')

describe('mep.chrome.config', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  it('has winbar/statuscolumn disabled by default, statusline/tabline/border enabled', function()
    assert.is_true(config.defaults.statusline.enable)
    assert.is_false(config.defaults.winbar.enable)
    assert.is_true(config.defaults.tabline.enable)
    assert.is_false(config.defaults.statuscolumn.enable)
    assert.is_true(config.defaults.border.enable)
  end)

  it('defaults statusline to a single full-width horizontal-line widget', function()
    local widgets = config.defaults.statusline.widgets
    assert.are.equal(1, #widgets)
    assert.is_function(widgets[1].text)
  end)

  it('the default line widget fills the window width with an unbroken line', function()
    local win = vim.api.nvim_get_current_win()
    local text = config.defaults.statusline.widgets[1].text({ win = win })
    local width = vim.api.nvim_win_get_width(win)
    assert.are.equal(width, vim.fn.strdisplaywidth(text))
    assert.are.equal(string.rep('─', width), text)
  end)

  it('defaults tabline.widgets_before to a single mode-indicator widget', function()
    local widgets = config.defaults.tabline.widgets_before
    assert.are.equal(1, #widgets)
    assert.is_function(widgets[1].text)
    assert.are.equal('ModeMsg', widgets[1].hl)
  end)

  it('defaults tabline.widgets_after to +/x widgets that open/close a tab', function()
    local widgets = config.defaults.tabline.widgets_after
    assert.are.equal(2, #widgets)
    assert.are.equal(' + ', widgets[1].text)
    assert.are.equal(' x ', widgets[2].text)
    assert.is_function(widgets[1].on_click)
    assert.is_function(widgets[2].on_click)
  end)

  it('defaults tabline.widgets_buttons to five panel-toggle widgets', function()
    local widgets = config.defaults.tabline.widgets_buttons
    assert.are.equal(5, #widgets)
    for _, widget in ipairs(widgets) do
      assert.is_function(widget.text)
      assert.is_function(widget.on_click)
    end
  end)

  it('enables all four border sides by default', function()
    assert.are.same({ left = true, right = true, top = true, bottom = true }, config.defaults.border.sides)
  end)

  it('setup() deep-merges onto a fresh copy of the defaults', function()
    local options = config.setup({ winbar = { enable = true } })
    assert.is_true(options.winbar.enable)
    assert.is_true(options.statusline.enable) -- untouched, still the default
    assert.is_true(options.border.enable) -- untouched
  end)

  it('setup() does not mutate config.defaults', function()
    config.setup({ border = { sides = { left = false } } })
    assert.is_true(config.defaults.border.sides.left)
  end)

  it('setup(nil) resets to the defaults', function()
    config.setup({ statusline = { enable = false } })
    config.setup(nil)
    assert.is_true(config.options.statusline.enable)
  end)
end)

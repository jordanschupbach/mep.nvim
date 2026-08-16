-- Real floating windows throughout (no mocking needed — floating
-- windows/buffers/uv timers all work fine under nlua, see spec/
-- README.md). Auto-dismiss tests use a tiny `timeout` override (real
-- ms, via vim.wait) rather than the real multi-second config defaults.
local popup = require('mep.notify.popup')
local config = require('mep.notify.config')

describe('mep.notify.popup', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    popup._reset()
  end)

  after_each(function()
    popup._reset()
    config.options = saved_options
  end)

  local function entry(text, level, title)
    return { text = text, level = level or vim.log.levels.INFO, title = title }
  end

  it('shows a toast as a real floating window', function()
    local win = popup.show(entry('hello'), { timeout = 0 })
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal(1, popup.count())
  end)

  it('colors the border by level', function()
    local win = popup.show(entry('oops', vim.log.levels.ERROR), { timeout = 0 })
    assert.matches('FloatBorder:MepNotifyError', vim.wo[win].winhighlight)
  end)

  it('includes the level icon and title (or a level label, if untitled) as the header line', function()
    local win = popup.show(entry('body text', vim.log.levels.WARN, 'Heads up'), { timeout = 0 })
    local buf = vim.api.nvim_win_get_buf(win)
    local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    assert.matches('⚠', first_line)
    assert.matches('Heads up', first_line)
  end)

  it('falls back to a plain level label when no title is given', function()
    local win = popup.show(entry('just a message', vim.log.levels.INFO), { timeout = 0 })
    local buf = vim.api.nvim_win_get_buf(win)
    local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    assert.matches('Info', first_line)
  end)

  it('wraps long text to max_width', function()
    config.setup({ max_width = 20, min_width = 10 })
    local win = popup.show(entry(string.rep('word ', 20)), { timeout = 0 })
    local cfg = vim.api.nvim_win_get_config(win)
    assert.is_true(cfg.width <= 20)
    local buf = vim.api.nvim_win_get_buf(win)
    assert.is_true(#vim.api.nvim_buf_get_lines(buf, 0, -1, false) > 1)
  end)

  it('stacks multiple toasts without overlapping rows', function()
    local win1 = popup.show(entry('first'), { timeout = 0 })
    local win2 = popup.show(entry('second'), { timeout = 0 })
    local cfg1 = vim.api.nvim_win_get_config(win1)
    local cfg2 = vim.api.nvim_win_get_config(win2)
    assert.are_not.equal(cfg1.row, cfg2.row)
  end)

  it('evicts the oldest toast once max_visible is reached', function()
    local first = popup.show(entry('one'), { timeout = 0, max_visible = 2 })
    popup.show(entry('two'), { timeout = 0, max_visible = 2 })
    popup.show(entry('three'), { timeout = 0, max_visible = 2 })
    assert.are.equal(2, popup.count())
    assert.is_false(vim.api.nvim_win_is_valid(first))
  end)

  it('auto-dismisses after its timeout elapses', function()
    popup.show(entry('brief'), { timeout = 20 })
    assert.are.equal(1, popup.count())
    vim.wait(500, function()
      return popup.count() == 0
    end, 10)
    assert.are.equal(0, popup.count())
  end)

  it('does not auto-dismiss when timeout is 0', function()
    popup.show(entry('sticky'), { timeout = 0 })
    vim.wait(60, function()
      return false
    end, 10)
    assert.are.equal(1, popup.count())
  end)

  it('dismiss_all closes every visible toast immediately', function()
    popup.show(entry('a'), { timeout = 0 })
    popup.show(entry('b'), { timeout = 0 })
    popup.dismiss_all()
    assert.are.equal(0, popup.count())
  end)

  it('reflows the remaining toast into the corner slot once the closer one auto-dismisses', function()
    local far = popup.show(entry('first'), { timeout = 0 }) -- sticky, farther from the corner
    local near = popup.show(entry('second'), { timeout = 20 }) -- newest, closest to the corner, dismisses soon
    local row_far_before = vim.api.nvim_win_get_config(far).row
    local row_near = vim.api.nvim_win_get_config(near).row
    assert.are_not.equal(row_far_before, row_near)

    vim.wait(500, function()
      return popup.count() == 1
    end, 10)
    assert.are.equal(1, popup.count())

    local row_far_after = vim.api.nvim_win_get_config(far).row
    assert.are.equal(row_near, row_far_after)
  end)

  it('positions toasts near the right edge for a "-right" position', function()
    config.setup({ position = 'top-right' })
    local win = popup.show(entry('x'), { timeout = 0 })
    local cfg = vim.api.nvim_win_get_config(win)
    assert.is_true(cfg.col + cfg.width > vim.o.columns / 2)
  end)

  it('positions toasts near the left edge for a "-left" position', function()
    config.setup({ position = 'top-left' })
    local win = popup.show(entry('x'), { timeout = 0 })
    local cfg = vim.api.nvim_win_get_config(win)
    assert.is_true(cfg.col < vim.o.columns / 2)
  end)
end)

local statusline = require('mep.chrome.statusline')
local config = require('mep.chrome.config')
local hover = require('mep.chrome.hover')

describe('mep.chrome.statusline', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    statusline.disable()
    config.options = saved_options
  end)

  describe('enable/disable', function()
    it('enable() installs the funcref, disable() restores the previous value', function()
      local saved = vim.o.statusline
      statusline.enable()
      assert.are.equal("%{%v:lua.require'mep.chrome.statusline'.eval()%}", vim.o.statusline)
      statusline.disable()
      assert.are.equal(saved, vim.o.statusline)
    end)

    it('enable() raises laststatus from 0 so the bar is actually visible', function()
      local saved = vim.o.laststatus
      vim.o.laststatus = 0
      statusline.enable()
      assert.are.equal(2, vim.o.laststatus)
      statusline.disable()
      vim.o.laststatus = saved
    end)

    it('enable() leaves a non-zero laststatus untouched', function()
      local saved = vim.o.laststatus
      vim.o.laststatus = 3
      statusline.enable()
      assert.are.equal(3, vim.o.laststatus)
      statusline.disable()
      vim.o.laststatus = saved
    end)

    it('is idempotent', function()
      assert.has_no.errors(function()
        statusline.enable()
        statusline.enable()
      end)
    end)
  end)

  describe('eval()', function()
    it('renders the configured widgets for the window in g:statusline_winid', function()
      config.setup({ statusline = { widgets = { { text = 'hello' } } } })
      vim.g.statusline_winid = vim.api.nvim_get_current_win()
      assert.are.equal('hello', statusline.eval())
    end)

    it('falls back to the current window when g:statusline_winid is unset', function()
      config.setup({ statusline = { widgets = { { text = function(ctx) return tostring(ctx.win) end } } } })
      vim.g.statusline_winid = nil
      assert.are.equal(tostring(vim.api.nvim_get_current_win()), statusline.eval())
    end)

    it('sets ctx.active based on whether win is the current window', function()
      config.setup({ statusline = { widgets = { { text = function(ctx) return ctx.active and 'yes' or 'no' end } } } })
      vim.g.statusline_winid = vim.api.nvim_get_current_win()
      assert.are.equal('yes', statusline.eval())
    end)

    it('feeds the rendered ranges to mep.chrome.hover for that window', function()
      config.setup({ statusline = { widgets = { { text = 'ab' } } } })
      local win = vim.api.nvim_get_current_win()
      vim.g.statusline_winid = win

      local orig_set_ranges = hover.set_ranges
      local seen
      hover.set_ranges = function(target, w, ranges)
        seen = { target = target, win = w, ranges = ranges }
        return orig_set_ranges(target, w, ranges)
      end
      statusline.eval()
      hover.set_ranges = orig_set_ranges

      assert.are.equal('statusline', seen.target)
      assert.are.equal(win, seen.win)
      assert.are.equal(1, #seen.ranges)
    end)
  end)
end)

local winbar = require('mep.chrome.winbar')
local config = require('mep.chrome.config')

describe('mep.chrome.winbar', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    winbar.disable()
    config.options = saved_options
  end)

  describe('enable/disable', function()
    it('enable() installs the funcref, disable() restores the previous value', function()
      local saved = vim.o.winbar
      winbar.enable()
      assert.are.equal("%{%v:lua.require'mep.chrome.winbar'.eval()%}", vim.o.winbar)
      winbar.disable()
      assert.are.equal(saved, vim.o.winbar)
    end)

    it('is idempotent', function()
      assert.has_no.errors(function()
        winbar.enable()
        winbar.enable()
      end)
    end)
  end)

  describe('eval()', function()
    it('renders the configured widgets for the window in g:statusline_winid', function()
      config.setup({ winbar = { widgets = { { text = 'top bar' } } } })
      vim.g.statusline_winid = vim.api.nvim_get_current_win()
      assert.are.equal('top bar', winbar.eval())
    end)

    it('falls back to the current window when g:statusline_winid is unset', function()
      config.setup({ winbar = { widgets = { { text = function(ctx) return tostring(ctx.win) end } } } })
      vim.g.statusline_winid = nil
      assert.are.equal(tostring(vim.api.nvim_get_current_win()), winbar.eval())
    end)
  end)
end)

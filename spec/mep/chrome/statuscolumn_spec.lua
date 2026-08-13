local statuscolumn = require('mep.chrome.statuscolumn')
local config = require('mep.chrome.config')

--- `v:lnum`/`v:relnum`/`v:virtnum` are read-only Neovim variables that
--- only take on meaningful values while 'statuscolumn' is genuinely
--- being evaluated for a given screen line — they can't be poked
--- directly from a spec. `nvim_eval_statusline`'s `use_statuscol_lnum`
--- lets Neovim itself set them for a real line, which is what these
--- tests drive through instead of calling `statuscolumn.eval()` bare.
local function eval_for_line(lnum)
  local win = vim.api.nvim_get_current_win()
  return vim.api.nvim_eval_statusline(vim.o.statuscolumn, { winid = win, use_statuscol_lnum = lnum }).str
end

describe('mep.chrome.statuscolumn', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
  end)

  after_each(function()
    statuscolumn.disable()
    config.options = saved_options
  end)

  describe('enable/disable', function()
    it('enable() installs the funcref, disable() restores the previous value', function()
      local saved = vim.o.statuscolumn
      statuscolumn.enable()
      assert.are.equal("%{%v:lua.require'mep.chrome.statuscolumn'.eval()%}", vim.o.statuscolumn)
      statuscolumn.disable()
      assert.are.equal(saved, vim.o.statuscolumn)
    end)

    it('is idempotent', function()
      assert.has_no.errors(function()
        statuscolumn.enable()
        statuscolumn.enable()
      end)
    end)
  end)

  describe('eval()', function()
    it('includes %s and %C when signs/folds are enabled (the default)', function()
      local text = statuscolumn.eval()
      assert.is_not_nil(text:match('%%s'))
      assert.is_not_nil(text:match('%%C'))
    end)

    it('omits %s/%C when signs/folds are disabled', function()
      config.setup({ statuscolumn = { signs = false, folds = false } })
      local text = statuscolumn.eval()
      assert.is_nil(text:match('%%s'))
      assert.is_nil(text:match('%%C'))
    end)

    it('shows the line number for a real, non-wrapped line', function()
      config.setup({ statuscolumn = { signs = false, folds = false } })
      statuscolumn.enable()
      assert.is_not_nil(eval_for_line(2):match('2'))
    end)

    it('renders configured widgets', function()
      config.setup({ statuscolumn = { widgets = { { text = 'W' } } } })
      local text = statuscolumn.eval()
      assert.is_not_nil(text:match('W'))
    end)
  end)
end)

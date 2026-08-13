local tabline = require('mep.chrome.tabline')
local config = require('mep.chrome.config')
local click = require('mep.chrome.click')

--- Every click-dispatch id appearing in rendered tabline text, in
--- render order — with the default config that's one per circle (tab
--- index order), then the `+`/`x` widgets.
local function click_ids(text)
  local ids = {}
  for id in text:gmatch('%%(%d+)@v:lua%.MepChromeClickDispatch@') do
    ids[#ids + 1] = tonumber(id)
  end
  return ids
end

describe('mep.chrome.tabline', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    tabline.disable()
    config.options = saved_options
  end)

  describe('enable/disable', function()
    it('enable() installs the funcref, disable() restores the previous value', function()
      local saved = vim.o.tabline
      tabline.enable()
      assert.are.equal("%{%v:lua.require'mep.chrome.tabline'.eval()%}", vim.o.tabline)
      tabline.disable()
      assert.are.equal(saved, vim.o.tabline)
    end)

    it('raises showtabline from 1 (only-when-multiple) to 2 (always)', function()
      local saved = vim.o.showtabline
      vim.o.showtabline = 1
      tabline.enable()
      assert.are.equal(2, vim.o.showtabline)
      tabline.disable()
      vim.o.showtabline = saved
    end)

    it('is idempotent', function()
      assert.has_no.errors(function()
        tabline.enable()
        tabline.enable()
      end)
    end)

    it('enable() forces a tabline redraw on every mode change', function()
      tabline.enable()
      local orig_cmd = vim.cmd
      local seen
      vim.cmd = function(c)
        if c == 'redrawtabline' then
          seen = true
        end
        return orig_cmd(c)
      end
      vim.api.nvim_exec_autocmds('ModeChanged', {})
      vim.cmd = orig_cmd
      assert.is_true(seen)
    end)

    it('disable() stops forcing a redraw on mode change', function()
      tabline.enable()
      tabline.disable()
      local orig_cmd = vim.cmd
      local seen = false
      vim.cmd = function(c)
        if c == 'redrawtabline' then
          seen = true
        end
        return orig_cmd(c)
      end
      vim.api.nvim_exec_autocmds('ModeChanged', {})
      vim.cmd = orig_cmd
      assert.is_false(seen)
    end)
  end)

  describe('eval()', function()
    it('renders a filled circle for the (only) current tab, no hollow ones', function()
      local text = tabline.eval()
      assert.is_not_nil(text:find('●', 1, true))
      assert.is_nil(text:find('○', 1, true))
    end)

    it('renders a hollow circle for a non-current tab alongside the filled one', function()
      vim.cmd('tabnew')
      local text = tabline.eval()
      assert.is_not_nil(text:find('●', 1, true))
      assert.is_not_nil(text:find('○', 1, true))
      vim.cmd('tabclose')
    end)

    it('highlights the current tab circle with TabLineSel, others with TabLine', function()
      vim.cmd('tabnew')
      local text = tabline.eval()
      assert.is_not_nil(text:match('#TabLineSel#[^#]*●'))
      assert.is_not_nil(text:match('#TabLine#[^#]*○'))
      vim.cmd('tabclose')
    end)

    it('clicking a circle switches to that tab', function()
      vim.cmd('tabnew')
      vim.cmd('tabnew') -- 3 tabs, current is tab 3
      local ids = click_ids(tabline.eval())
      click.dispatch(ids[1], 1, 'l', '')
      assert.are.equal(1, vim.fn.tabpagenr())
      vim.cmd('tabclose')
      vim.cmd('tabclose')
    end)

    it('re-renders with the same click ids for the same tabs (stable widget identity)', function()
      vim.cmd('tabnew')
      local ids_a = click_ids(tabline.eval())
      local ids_b = click_ids(tabline.eval())
      assert.are.same(ids_a, ids_b)
      vim.cmd('tabclose')
    end)

    it('ends with a TabLineFill reset', function()
      local text = tabline.eval()
      assert.is_not_nil(text:match('#TabLineFill#$'))
    end)

    it('renders widgets_before ahead of the circles', function()
      config.setup({ tabline = { widgets_before = { { text = 'BEFORE' } }, widgets_after = {} } })
      local text = tabline.eval()
      assert.are.equal(1, (text:find('BEFORE', 1, true)))
      assert.is_true(text:find('BEFORE', 1, true) < text:find('●', 1, true))
    end)

    it('renders widgets_after behind the circles', function()
      config.setup({ tabline = { widgets_before = {}, widgets_after = { { text = 'AFTER' } } } })
      local text = tabline.eval()
      assert.is_not_nil(text:find('AFTER', 1, true))
      assert.is_true(text:find('●', 1, true) < text:find('AFTER', 1, true))
    end)

    it('shows the current mode by default', function()
      local text = tabline.eval()
      assert.is_not_nil(text:find('Normal', 1, true))
    end)

    it('the default + widget opens a new tab', function()
      local before = #vim.api.nvim_list_tabpages()
      config.options.tabline.widgets_after[1].on_click()
      assert.are.equal(before + 1, #vim.api.nvim_list_tabpages())
      vim.cmd('tabclose')
    end)

    it('the default x widget closes the current tab', function()
      vim.cmd('tabnew')
      local before = #vim.api.nvim_list_tabpages()
      config.options.tabline.widgets_after[2].on_click()
      assert.are.equal(before - 1, #vim.api.nvim_list_tabpages())
    end)

    it('the default x widget is a harmless no-op on the last tab', function()
      assert.are.equal(1, #vim.api.nvim_list_tabpages())
      assert.has_no.errors(function()
        config.options.tabline.widgets_after[2].on_click()
      end)
      assert.are.equal(1, #vim.api.nvim_list_tabpages())
    end)
  end)
end)

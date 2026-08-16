-- mep.activitybar/mep.filetree/mep.symbols/mep.chrome are all mocked
-- via package.loaded — mep.zen's own dependency on each is soft
-- (pcall'd require), so this exercises the orchestration logic without
-- needing any of those libraries' own real behavior. mep.zen.layout's
-- centering runs for real (see spec/mep/zen/layout_spec.lua for its own
-- dedicated coverage) — plain vsplit windows, cleaned up via `only`.
local zen = require('mep.zen')
local config = require('mep.zen.config')

describe('mep.zen', function()
  local saved_options
  local orig_activitybar, orig_filetree, orig_symbols, orig_chrome, orig_chrome_config

  local function make_fake_sidebar(open)
    local self = { open_calls = 0, close_calls = 0 }
    function self:is_open()
      return open
    end
    function self:open()
      open = true
      self.open_calls = self.open_calls + 1
    end
    function self:close()
      open = false
      self.close_calls = self.close_calls + 1
    end
    return self
  end

  local function make_fake_toggleable(open)
    return {
      is_open = function()
        return open
      end,
      open = function()
        open = true
      end,
      close = function()
        open = false
      end,
    }
  end

  local function make_fake_chrome_target(enabled)
    return {
      enable = function()
        enabled = true
      end,
      disable = function()
        enabled = false
      end,
      is_enabled = function()
        return enabled
      end,
    }
  end

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_activitybar = package.loaded['mep.activitybar']
    orig_filetree = package.loaded['mep.filetree']
    orig_symbols = package.loaded['mep.symbols']
    orig_chrome = package.loaded['mep.chrome']
    orig_chrome_config = package.loaded['mep.chrome.config']
    pcall(vim.cmd, 'only')

    -- Safe no-op defaults for every test — never touches the real
    -- modules (which would tamper with real global editor state shared
    -- across every other spec file in this same busted run) unless a
    -- test overrides one of these itself, below.
    package.loaded['mep.activitybar'] = { bar = function()
      return make_fake_sidebar(false)
    end }
    package.loaded['mep.filetree'] = make_fake_toggleable(false)
    package.loaded['mep.symbols'] = make_fake_toggleable(false)
    package.loaded['mep.chrome'] = {
      statusline = make_fake_chrome_target(false),
      winbar = make_fake_chrome_target(false),
      statuscolumn = make_fake_chrome_target(false),
    }
    package.loaded['mep.chrome.config'] = {
      options = {
        statusline = { enable = false },
        winbar = { enable = false },
        statuscolumn = { enable = false },
      },
    }
  end)

  after_each(function()
    zen._reset()
    config.options = saved_options
    package.loaded['mep.activitybar'] = orig_activitybar
    package.loaded['mep.filetree'] = orig_filetree
    package.loaded['mep.symbols'] = orig_symbols
    package.loaded['mep.chrome'] = orig_chrome
    package.loaded['mep.chrome.config'] = orig_chrome_config
    pcall(vim.cmd, 'only')
  end)

  describe('is_active', function()
    it('is false until enable()', function()
      assert.is_false(zen.is_active())
    end)
  end)

  describe('enable / disable', function()
    it('closes an open activitybar bar and reopens it on disable', function()
      local bar = make_fake_sidebar(true)
      package.loaded['mep.activitybar'] = { bar = function()
        return bar
      end }

      zen.enable()
      assert.are.equal(1, bar.close_calls)
      assert.is_true(zen.is_active())

      zen.disable()
      assert.are.equal(1, bar.open_calls)
    end)

    it('leaves an already-closed activitybar bar closed on disable', function()
      local bar = make_fake_sidebar(false)
      package.loaded['mep.activitybar'] = { bar = function()
        return bar
      end }

      zen.enable()
      zen.disable()
      assert.are.equal(0, bar.close_calls)
      assert.are.equal(0, bar.open_calls)
    end)

    it('closes an open filetree and reopens it on disable', function()
      local filetree = make_fake_toggleable(true)
      package.loaded['mep.filetree'] = filetree

      zen.enable()
      assert.is_false(filetree.is_open())
      zen.disable()
      assert.is_true(filetree.is_open())
    end)

    it('closes an open symbols outline and reopens it on disable', function()
      local symbols = make_fake_toggleable(true)
      package.loaded['mep.symbols'] = symbols

      zen.enable()
      assert.is_false(symbols.is_open())
      zen.disable()
      assert.is_true(symbols.is_open())
    end)

    it('suppresses and restores the gutter on the enabling window', function()
      vim.wo[0].number = true
      zen.enable()
      assert.is_false(vim.wo[0].number)
      zen.disable()
      assert.is_true(vim.wo[0].number)
    end)

    it('disables configured-on chrome targets and re-enables only those on disable', function()
      local statusline = make_fake_chrome_target(true)
      local winbar = make_fake_chrome_target(false)
      local statuscolumn = make_fake_chrome_target(true)
      package.loaded['mep.chrome'] = { statusline = statusline, winbar = winbar, statuscolumn = statuscolumn }
      package.loaded['mep.chrome.config'] = {
        options = {
          statusline = { enable = true },
          winbar = { enable = false },
          statuscolumn = { enable = true },
        },
      }

      zen.enable()
      assert.is_false(statusline.is_enabled())
      assert.is_false(winbar.is_enabled())
      assert.is_false(statuscolumn.is_enabled())

      zen.disable()
      assert.is_true(statusline.is_enabled())
      assert.is_false(winbar.is_enabled()) -- was never on; stays off
      assert.is_true(statuscolumn.is_enabled())
    end)

    it('centers the current window', function()
      local win = vim.api.nvim_get_current_win()
      config.setup({ width = 90 })
      zen.enable()
      -- minimal_init.lua sets columns = 120 -> two 15-column padding
      -- splits appear.
      assert.are.equal(3, #vim.api.nvim_tabpage_list_wins(0))
      zen.disable()
      assert.are.equal(1, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal(win, vim.api.nvim_get_current_win())
    end)

    it('respects config.hide to skip a piece entirely', function()
      config.setup({ hide = { gutter = false } })
      vim.wo[0].number = true
      zen.enable()
      assert.is_true(vim.wo[0].number)
      zen.disable()
    end)

    it('enable() is a no-op when already active', function()
      zen.enable()
      local win_count_after_first = #vim.api.nvim_tabpage_list_wins(0)
      zen.enable()
      assert.are.equal(win_count_after_first, #vim.api.nvim_tabpage_list_wins(0))
      zen.disable()
    end)

    it('disable() is a no-op when not active', function()
      assert.has_no.errors(function()
        zen.disable()
      end)
    end)
  end)

  describe('toggle', function()
    it('enables then disables on alternating calls', function()
      zen.toggle()
      assert.is_true(zen.is_active())
      zen.toggle()
      assert.is_false(zen.is_active())
    end)
  end)

  describe('setup', function()
    it('returns the resolved options', function()
      local options = zen.setup({ width = 100, keymaps = { toggle = { '<localleader>zz2' } } })
      assert.are.equal(100, options.width)
      pcall(vim.keymap.del, 'n', '<localleader>zz2')
    end)

    it('binds the configured toggle keymap', function()
      local keymaps = { toggle = { '<localleader>zz1' } }
      zen.setup({ keymaps = keymaps })

      local found = false
      for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
        if m.lhs == vim.api.nvim_replace_termcodes(keymaps.toggle[1], true, false, true) then
          found = true
        end
      end
      assert.is_true(found)

      pcall(vim.keymap.del, 'n', keymaps.toggle[1])
    end)
  end)
end)

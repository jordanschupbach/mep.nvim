local keys = require('mep.core.keys')
local config = require('mep.config')

describe('mep.core.keys', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    -- Modules (and therefore mep.config.options) are cached across the
    -- whole busted run — restore so a configured mod doesn't leak into
    -- other spec files' own setup() calls.
    config.options = saved_options
  end)

  describe('resolve()', function()
    it('falls back to the platform default for mod1 (Alt, or Option-as-Meta on macOS)', function()
      config.setup({})
      local expected = vim.fn.has('mac') == 1 and 'M' or 'A'
      assert.are.equal(expected, keys.resolve('mod1'))
    end)

    it('prefers a user-configured mods value over the platform default', function()
      config.setup({ mods = { mod1 = 'D' } })
      assert.are.equal('D', keys.resolve('mod1'))
    end)

    it('is case-insensitive on the name', function()
      config.setup({ mods = { mod1 = 'D' } })
      assert.are.equal('D', keys.resolve('Mod1'))
    end)

    it('returns nil for a modifier with no config and no fallback', function()
      config.setup({})
      assert.is_nil(keys.resolve('mod2'))
    end)

    it('resolves additional modN names once configured', function()
      config.setup({ mods = { mod2 = 'C' } })
      assert.are.equal('C', keys.resolve('mod2'))
    end)

    it('ignores a non-string or empty configured value', function()
      config.setup({ mods = { mod1 = '' } })
      local expected = vim.fn.has('mac') == 1 and 'M' or 'A'
      assert.are.equal(expected, keys.resolve('mod1'))
    end)
  end)

  describe('expand()', function()
    before_each(function()
      config.setup({ mods = { mod1 = 'A' } })
    end)

    it('rewrites a bare <Mod1-key>', function()
      assert.are.equal('<A-h>', keys.expand('<Mod1-h>'))
    end)

    it('keeps extra modifiers and special keys intact', function()
      assert.are.equal('<A-S-Left>', keys.expand('<Mod1-S-Left>'))
      assert.are.equal('<A-C-h>', keys.expand('<Mod1-C-h>'))
      assert.are.equal('<A-CR>', keys.expand('<Mod1-CR>'))
    end)

    it('accepts any capitalization of the placeholder', function()
      assert.are.equal('<A-x>', keys.expand('<mod1-x>'))
      assert.are.equal('<A-x>', keys.expand('<MOD1-x>'))
    end)

    it('expands every occurrence in a multi-chord lhs', function()
      assert.are.equal('<A-w><A-q>', keys.expand('<Mod1-w><Mod1-q>'))
    end)

    it('leaves strings without placeholders untouched', function()
      assert.are.equal('<C-c><C-t>', keys.expand('<C-c><C-t>'))
      assert.are.equal('<leader>x', keys.expand('<leader>x'))
    end)

    it('leaves an unconfigured modN placeholder as-is', function()
      assert.are.equal('<Mod2-h>', keys.expand('<Mod2-h>'))
    end)

    it('expands a configured modN alongside mod1', function()
      config.setup({ mods = { mod1 = 'A', mod2 = 'C' } })
      assert.are.equal('<C-x>', keys.expand('<Mod2-x>'))
    end)

    it('passes non-strings through untouched', function()
      assert.is_nil(keys.expand(nil))
      assert.are.equal(3, keys.expand(3))
    end)
  end)

  describe('expand_table()', function()
    it('expands nested string values in place and returns the table', function()
      config.setup({ mods = { mod1 = 'A' } })
      local tbl = {
        keymaps = {
          focus_left = { '<Mod1-h>' },
          next_tab = { '<Mod1-n>', '<Mod1-Tab>' },
          cycle_todo = { '<C-c><C-t>' },
        },
        resize_step = 3,
      }
      local result = keys.expand_table(tbl)
      assert.are.equal(tbl, result)
      assert.are.same({ '<A-h>' }, tbl.keymaps.focus_left)
      assert.are.same({ '<A-n>', '<A-Tab>' }, tbl.keymaps.next_tab)
      assert.are.same({ '<C-c><C-t>' }, tbl.keymaps.cycle_todo)
      assert.are.equal(3, tbl.resize_step)
    end)
  end)

  describe('library config integration', function()
    it('a global mods override retargets a library default at its setup()', function()
      config.setup({ mods = { mod1 = 'D' } })
      local window_config = require('mep.window.config')
      local saved = vim.deepcopy(window_config.options)
      local opts = window_config.setup({})
      assert.are.same({ '<D-v>' }, opts.manual.keymaps.split_vertical)
      window_config.options = saved
    end)

    it('user-supplied keymaps get the same expansion as the defaults', function()
      config.setup({ mods = { mod1 = 'A' } })
      local window_config = require('mep.window.config')
      local saved = vim.deepcopy(window_config.options)
      local opts = window_config.setup({ manual = { keymaps = { remove = { '<Mod1-x>' } } } })
      assert.are.same({ '<A-x>' }, opts.manual.keymaps.remove)
      window_config.options = saved
    end)
  end)
end)

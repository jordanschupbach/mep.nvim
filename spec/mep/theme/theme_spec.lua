-- Applying a theme calls `highlight clear` (see mep.theme.engine.apply)
-- — a real, global, persistent side effect, the same as a real user's
-- own `:colorscheme` — so these tests always leave *some* real theme
-- applied when they're done, same as the rest of a real Neovim session
-- would. That's expected, not cleaned up away.
local theme = require('mep.theme')
local config = require('mep.theme.config')
local palettes = require('mep.theme.palettes')

describe('mep.theme', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    theme._reset()
  end)

  after_each(function()
    theme._reset()
    config.options = saved_config
    palettes.palettes['mep-test-custom'] = nil
    -- Several tests above call theme.setup() with default keymaps
    -- (only the one test that overrides keymaps.picker cleans up its
    -- own <F6> itself) — binding the real default <leader>ut globally
    -- with no per-test cleanup would otherwise leak into whichkey's own
    -- registry_spec.lua, the same class of bug seen with mep.git/mep.
    -- window's own global keymaps.
    for _, lhs in ipairs(config.defaults.keymaps.picker) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  describe('apply / current', function()
    it('is nil before anything has been applied', function()
      assert.is_nil(theme.current())
    end)

    it('applies a known theme and updates current()', function()
      theme.apply('nord')
      assert.are.equal('nord', theme.current())
      assert.are.equal('dark', vim.o.background)
    end)

    it('warns and leaves current() unchanged for an unknown theme', function()
      theme.apply('gruvbox-dark')
      local orig_notify = vim.notify
      local warned
      vim.notify = function(_, level)
        warned = level
      end
      theme.apply('not-a-real-theme')
      vim.notify = orig_notify
      assert.are.equal(vim.log.levels.WARN, warned)
      assert.are.equal('gruvbox-dark', theme.current())
    end)

    it('errors (via notify) instead of applying a palette missing required fields', function()
      theme.register('mep-test-custom', { dark = true, bg = '#000000' }) -- missing fg, accent hues, border
      theme.apply('gruvbox-dark')
      local orig_notify = vim.notify
      local level
      vim.notify = function(_, lvl)
        level = lvl
      end
      theme.apply('mep-test-custom')
      vim.notify = orig_notify
      assert.are.equal(vim.log.levels.ERROR, level)
      assert.are.equal('gruvbox-dark', theme.current())
    end)
  end)

  describe('register / list', function()
    it('makes a newly-registered theme immediately applicable', function()
      theme.register('mep-test-custom', {
        dark = true,
        bg = '#000000',
        fg = '#ffffff',
        red = '#ff0000',
        green = '#00ff00',
        yellow = '#ffff00',
        blue = '#0000ff',
        purple = '#ff00ff',
        cyan = '#00ffff',
        orange = '#ff8800',
        border = '#333333',
      })
      assert.is_not_nil(vim.tbl_contains(theme.list(), 'mep-test-custom'))
      theme.apply('mep-test-custom')
      assert.are.equal('mep-test-custom', theme.current())
    end)

    it('list() is sorted and includes the built-ins', function()
      local names = theme.list()
      local sorted = vim.deepcopy(names)
      table.sort(sorted)
      assert.are.same(sorted, names)
      assert.is_not_nil(vim.tbl_contains(names, 'nord'))
    end)
  end)

  describe('setup', function()
    it('applies options.default by default', function()
      theme.setup({ default = 'dracula' })
      assert.are.equal('dracula', theme.current())
    end)

    it('does not apply anything when apply_on_setup = false', function()
      theme.setup({ default = 'dracula', apply_on_setup = false })
      assert.is_nil(theme.current())
    end)

    it('binds the picker keymap', function()
      theme.setup({ apply_on_setup = false, keymaps = { picker = { '<F6>' } } })
      local maps = vim.api.nvim_get_keymap('n')
      local found = false
      for _, m in ipairs(maps) do
        if m.lhs == '<F6>' then
          found = true
        end
      end
      assert.is_true(found)
      pcall(vim.keymap.del, 'n', '<F6>')
    end)

    it('returns the resolved config', function()
      local opts = theme.setup({ apply_on_setup = false, default = 'nord' })
      assert.are.equal('nord', opts.default)
    end)
  end)

  describe('picker', function()
    local picker_mod = require('mep.picker')
    local orig_start

    before_each(function()
      orig_start = picker_mod.start
    end)

    after_each(function()
      picker_mod.start = orig_start
    end)

    it('lists every theme, marking the current one', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()
      assert.is_not_nil(vim.tbl_contains(captured.items, 'nord'))
      assert.matches('nord.*%(current%)', captured.entry_to_string('nord'))
      assert.are_not.matches('%(current%)', captured.entry_to_string('dracula'))
    end)

    it('puts the current theme first, so mep.picker (always starting at item 1) opens on it', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()
      assert.are.equal('nord', captured.items[1])
    end)

    it('preview applies the highlighted theme live', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()

      captured.preview('dracula')
      assert.are.equal('dracula', theme.current())
    end)

    it('preview also renders a color swatch into the preview sidebar buffer', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()

      local preview_buf = vim.api.nvim_create_buf(false, true)
      captured.preview('dracula', preview_buf, nil)

      local lines = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
      assert.are.equal('dracula', lines[1])
      assert.matches(palettes.palettes.dracula.bg, table.concat(lines, '\n'))

      pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
    end)

    it('on_close reverts to the theme that was active before the picker opened', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()

      captured.preview('dracula') -- live-previewed, not committed
      captured.on_close() -- Escape, <C-c>, or any other non-selecting close

      assert.are.equal('nord', theme.current())
    end)

    it('on_close is a harmless no-op when nothing was current before opening', function()
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()

      captured.preview('dracula')
      assert.has_no.errors(captured.on_close)
      assert.are.equal('dracula', theme.current()) -- nothing to revert to
    end)

    it('on_select commits the chosen theme', function()
      theme.apply('nord')
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end
      theme.picker()

      captured.preview('dracula')
      captured.on_close() -- mep.picker always closes before on_select fires
      captured.on_select('dracula')

      assert.are.equal('dracula', theme.current())
    end)
  end)
end)

local icons = require('mep.icons.icons')
local config = require('mep.icons.config')

describe('mep.icons.icons', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  describe('get_file_icon (default nerd_font style)', function()
    it('looks up by extension, case-insensitively', function()
      local icon, hl = icons.get_file_icon('foo.lua')
      assert.are.equal('\u{e620}', icon)
      assert.are.equal('MepIconFile', hl)

      local icon_upper = icons.get_file_icon('FOO.LUA')
      assert.are.equal('\u{e620}', icon_upper)
    end)

    it('looks up special filenames before falling back to extension', function()
      assert.are.equal('\u{e779}', icons.get_file_icon('Makefile'))
      assert.are.equal('\u{e702}', icons.get_file_icon('.gitignore'))
    end)

    it('resolves a full path down to its basename', function()
      assert.are.equal('\u{e620}', icons.get_file_icon('/some/deep/path/foo.lua'))
    end)

    it('falls back to the default file icon for an unknown extension', function()
      assert.are.equal('\u{f15b}', icons.get_file_icon('foo.zzz'))
    end)

    it('falls back to the default file icon when there is no extension at all', function()
      assert.are.equal('\u{f15b}', icons.get_file_icon('README'))
    end)
  end)

  describe('get_directory_icon', function()
    it('returns the closed icon by default and the open icon when expanded', function()
      local closed, hl = icons.get_directory_icon(false)
      assert.are.equal('\u{f07b}', closed)
      assert.are.equal('MepIconDirectory', hl)
      assert.are.equal('\u{f07c}', icons.get_directory_icon(true))
    end)
  end)

  describe('get_expand_marker', function()
    it('returns distinct closed/open markers', function()
      assert.are.equal('\u{f054}', icons.get_expand_marker(false))
      assert.are.equal('\u{f078}', icons.get_expand_marker(true))
    end)
  end)

  describe('emoji style', function()
    it('looks up by extension, case-insensitively', function()
      assert.are.equal('🌙', icons.get_file_icon('foo.lua', { style = 'emoji' }))
      assert.are.equal('🌙', icons.get_file_icon('FOO.LUA', { style = 'emoji' }))
    end)

    it('looks up special filenames before falling back to extension', function()
      assert.are.equal('🔨', icons.get_file_icon('Makefile', { style = 'emoji' }))
      assert.are.equal('🌿', icons.get_file_icon('.gitignore', { style = 'emoji' }))
    end)

    it('falls back to the default file icon for an unknown extension', function()
      assert.are.equal('📄', icons.get_file_icon('foo.zzz', { style = 'emoji' }))
    end)
  end)

  describe('style selection', function()
    it('honors a per-call opts.style override without touching global config', function()
      assert.are.equal('-', icons.get_file_icon('foo.lua', { style = 'ascii' }))
      -- global config untouched: next call with no opts uses nerd_font again
      assert.are.equal('\u{e620}', icons.get_file_icon('foo.lua'))
    end)

    it('honors the configured style once setup() is called', function()
      config.setup({ style = 'ascii' })
      assert.are.equal('-', icons.get_file_icon('foo.lua'))
      assert.are.equal('+', icons.get_directory_icon(false))
      assert.are.equal('>', icons.get_expand_marker(false))
    end)

    it('the ascii style has no per-extension differentiation, by design', function()
      config.setup({ style = 'ascii' })
      assert.are.equal(icons.get_file_icon('foo.lua'), icons.get_file_icon('foo.py'))
    end)

    it('the nerd_font style differentiates at least some extensions', function()
      local js_icon = icons.get_file_icon('foo.js')
      local default_icon = icons.get_file_icon('foo.zzz')
      assert.are_not.equal(js_icon, default_icon)
    end)
  end)

  describe('overrides', function()
    it('layers a custom icon on top of the built-in table', function()
      config.setup({ style = 'emoji', overrides = { emoji = { by_extension = { lua = '🌛' } } } })
      assert.are.equal('🌛', icons.get_file_icon('foo.lua'))
      -- other extensions are unaffected
      assert.are.equal('🐍', icons.get_file_icon('foo.py'))
    end)

    it('can override the default file icon', function()
      config.setup({ style = 'emoji', overrides = { emoji = { default_file = '❓' } } })
      assert.are.equal('❓', icons.get_file_icon('foo.zzz'))
    end)
  end)
end)

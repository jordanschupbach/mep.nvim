local engine = require('mep.theme.engine')

describe('mep.theme.engine', function()
  local minimal = {
    dark = true,
    bg = '#000001',
    fg = '#000002',
    red = '#000003',
    green = '#000004',
    yellow = '#000005',
    blue = '#000006',
    purple = '#000007',
    cyan = '#000008',
    orange = '#000009',
    border = '#00000a',
  }

  describe('missing_fields', function()
    it('is empty for a complete palette', function()
      assert.are.same({}, engine.missing_fields(minimal))
    end)

    it('lists every missing required field', function()
      local broken = vim.tbl_extend('force', {}, minimal)
      broken.red = nil
      broken.dark = nil
      local missing = engine.missing_fields(broken)
      table.sort(missing)
      assert.are.same({ 'dark', 'red' }, missing)
    end)
  end)

  describe('normalize', function()
    it('leaves a fully-specified palette untouched', function()
      local full = vim.tbl_extend('force', minimal, {
        bg_alt = '#111111',
        bg_float = '#222222',
        fg_alt = '#333333',
        selection = '#444444',
        accent = '#555555',
      })
      assert.are.same(full, engine.normalize(full))
    end)

    it('falls back bg_alt/fg_alt to bg/fg, accent to blue, selection to border', function()
      local p = engine.normalize(minimal)
      assert.are.equal(minimal.bg, p.bg_alt)
      assert.are.equal(minimal.fg, p.fg_alt)
      assert.are.equal(minimal.blue, p.accent)
      assert.are.equal(minimal.border, p.selection)
    end)

    it('falls bg_float back through bg_alt (dependency order)', function()
      local p = engine.normalize(vim.tbl_extend('force', minimal, { bg_alt = '#aabbcc' }))
      assert.are.equal('#aabbcc', p.bg_float)
    end)

    it('does not mutate the input palette', function()
      local copy = vim.deepcopy(minimal)
      engine.normalize(copy)
      assert.is_nil(copy.bg_alt)
    end)
  end)

  describe('build', function()
    it('resolves fg/bg to the palette colors they reference', function()
      local groups = engine.build(minimal)
      assert.are.same({ fg = minimal.fg, bg = minimal.bg }, groups.Normal)
      assert.are.same({ fg = minimal.red, bold = true }, groups.Error)
    end)

    it('resolves an sp (underline color) field', function()
      local groups = engine.build(minimal)
      assert.are.equal(minimal.red, groups.DiagnosticUnderlineError.sp)
      assert.is_true(groups.DiagnosticUnderlineError.underline)
    end)

    it('keeps a link entry as a bare link, not a color table', function()
      local groups = engine.build(minimal)
      assert.are.same({ link = 'String' }, groups['@string'])
    end)

    it('never emits an unresolved (nil) color for a defined fg/bg/sp', function()
      local groups = engine.build(minimal)
      for group, hl in pairs(groups) do
        if not hl.link then
          if hl.fg then
            assert.is_string(hl.fg, group .. '.fg')
          end
          if hl.bg then
            assert.is_string(hl.bg, group .. '.bg')
          end
          if hl.sp then
            assert.is_string(hl.sp, group .. '.sp')
          end
        end
      end
    end)

    it('works from a minimal palette missing every optional field', function()
      assert.has_no.errors(function()
        engine.build(minimal)
      end)
    end)
  end)

  describe('apply', function()
    local saved_background, saved_colors_name

    before_each(function()
      saved_background = vim.o.background
      saved_colors_name = vim.g.colors_name
    end)

    after_each(function()
      vim.o.background = saved_background
      vim.g.colors_name = saved_colors_name
    end)

    it('sets background and colors_name', function()
      engine.apply(vim.tbl_extend('force', minimal, { name = 'mep-test-theme' }))
      assert.are.equal('dark', vim.o.background)
      assert.are.equal('mep-test-theme', vim.g.colors_name)
    end)

    it('sets background to light for a light palette', function()
      local light = vim.tbl_extend('force', minimal, { dark = false, name = 'mep-test-light' })
      engine.apply(light)
      assert.are.equal('light', vim.o.background)
    end)

    it('actually sets real highlight groups', function()
      engine.apply(vim.tbl_extend('force', minimal, { name = 'mep-test-theme' }))
      local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
      assert.are.equal(0x000001, normal.bg)
      assert.are.equal(0x000002, normal.fg)
    end)

    it('fires a real ColorScheme autocmd event', function()
      local group = vim.api.nvim_create_augroup('MepThemeEngineSpec', { clear = true })
      local fired = false
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = group,
        callback = function()
          fired = true
        end,
      })
      engine.apply(vim.tbl_extend('force', minimal, { name = 'mep-test-theme' }))
      pcall(vim.api.nvim_del_augroup_by_id, group)
      assert.is_true(fired)
    end)
  end)
end)

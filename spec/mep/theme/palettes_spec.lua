local palettes = require('mep.theme.palettes')
local engine = require('mep.theme.engine')

describe('mep.theme.palettes', function()
  it('has a generous collection of themes', function()
    local count = 0
    for _ in pairs(palettes.palettes) do
      count = count + 1
    end
    assert.is_true(count >= 15, 'expected at least 15 built-in themes, got ' .. count)
  end)

  it('includes some well-known names', function()
    for _, name in ipairs({ 'gruvbox-dark', 'nord', 'dracula', 'tokyo-night', 'catppuccin-mocha', 'one-dark' }) do
      assert.is_not_nil(palettes.palettes[name], name .. ' should be a built-in theme')
    end
  end)

  it('has both dark and light themes', function()
    local dark, light = 0, 0
    for _, p in pairs(palettes.palettes) do
      if p.dark then
        dark = dark + 1
      else
        light = light + 1
      end
    end
    assert.is_true(dark > 0)
    assert.is_true(light > 0)
  end)

  describe('every palette', function()
    for name, palette in pairs(palettes.palettes) do
      it(name .. ' defines every required field with valid hex colors', function()
        local missing = engine.missing_fields(palette)
        assert.are.same({}, missing, name .. ' missing: ' .. table.concat(missing, ', '))

        for field, value in pairs(palette) do
          if field ~= 'dark' then
            assert.matches('^#%x%x%x%x%x%x$', value, name .. '.' .. field .. ' = ' .. tostring(value))
          end
        end
      end)
    end
  end)
end)

local swatch = require('mep.theme.swatch')
local engine = require('mep.theme.engine')
local palettes = require('mep.theme.palettes')

describe('mep.theme.swatch', function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it('is a no-op for an invalid buffer', function()
    assert.has_no.errors(function()
      swatch.render(99999999, 'nord', engine.normalize(palettes.palettes.nord))
    end)
  end)

  it('is a no-op when buf is nil (e.g. a test-captured preview(item) with no buf/win)', function()
    assert.has_no.errors(function()
      swatch.render(nil, 'nord', engine.normalize(palettes.palettes.nord))
    end)
  end)

  it('writes the theme name as the first line', function()
    swatch.render(buf, 'nord', engine.normalize(palettes.palettes.nord))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    assert.are.equal('nord', lines[1])
  end)

  it('writes one line per palette field, containing its hex value', function()
    local palette = engine.normalize(palettes.palettes.nord)
    swatch.render(buf, 'nord', palette)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n')
    for _, field in ipairs({ 'bg', 'fg', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'orange', 'border' }) do
      assert.matches(field, text)
      assert.matches(palette[field], text)
    end
  end)

  it('highlights each swatch block with a group whose bg matches that field', function()
    local palette = engine.normalize(palettes.palettes.nord)
    swatch.render(buf, 'nord', palette)
    local hl = vim.api.nvim_get_hl(0, { name = 'MepThemeSwatch_red' })
    assert.are.equal(palette.red, string.format('#%06x', hl.bg))
  end)

  it('leaves the buffer unmodifiable after rendering', function()
    swatch.render(buf, 'nord', engine.normalize(palettes.palettes.nord))
    assert.is_false(vim.bo[buf].modifiable)
  end)

  it('re-rendering a different theme replaces the previous content', function()
    swatch.render(buf, 'nord', engine.normalize(palettes.palettes.nord))
    swatch.render(buf, 'dracula', engine.normalize(palettes.palettes.dracula))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    assert.are.equal('dracula', lines[1])
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert.is_nil(text:find(palettes.palettes.nord.bg, 1, true))
  end)
end)

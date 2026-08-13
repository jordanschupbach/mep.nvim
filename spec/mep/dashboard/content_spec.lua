local content = require('mep.dashboard.content')
local mep_version = require('mep.version')

describe('mep.dashboard.content', function()
  describe('LOGO', function()
    it('is non-empty and every row has the same display width', function()
      assert.is_true(#content.LOGO > 0)
      local width = vim.fn.strdisplaywidth(content.LOGO[1])
      for _, row in ipairs(content.LOGO) do
        assert.are.equal(width, vim.fn.strdisplaywidth(row))
      end
    end)

    it('every row is made only of the block character and spaces', function()
      for _, row in ipairs(content.LOGO) do
        assert.is_true(row:find('█', 1, true) ~= nil)
        assert.are.equal('', (row:gsub('█', ''):gsub('%s', '')))
      end
    end)
  end)

  describe('default', function()
    local logo_height = 0
    before_each(function()
      logo_height = #content.LOGO
    end)

    it('opens with the logo, immediately followed by a blank line', function()
      local lines = content.default()
      for i, row in ipairs(content.LOGO) do
        assert.are.equal(row, lines[i])
      end
      assert.are.equal('', lines[logo_height + 1])
    end)

    it('includes the actually-running Neovim version, not a hardcoded one, right after the logo', function()
      local v = vim.version()
      local expected = string.format('NVIM v%d.%d.%d', v.major, v.minor, v.patch)
      local lines = content.default()
      assert.are.equal(expected, lines[logo_height + 2])
    end)

    it('shows the mep.nvim version directly below the Neovim version', function()
      local expected =
        string.format('MEP v%d.%d.%d', mep_version.major, mep_version.minor, mep_version.patch)
      local lines = content.default()
      assert.are.equal(expected, lines[logo_height + 3])
    end)

    it('references the correct major.minor "news" tag', function()
      local v = vim.version()
      local expected_tag = string.format('v%d.%d', v.major, v.minor)
      local lines = content.default()
      local found = false
      for _, l in ipairs(lines) do
        if l:match('news') then
          assert.matches(expected_tag, l, 1, true)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('mentions the standard help pointers', function()
      local text = table.concat(content.default(), '\n')
      assert.matches(':help nvim', text, 1, true)
      assert.matches(':checkhealth', text, 1, true)
      assert.matches(':help iccf', text, 1, true)
    end)

    it('returns a fresh table on every call', function()
      local a = content.default()
      local b = content.default()
      assert.are_not.equal(a, b) -- different tables
      assert.are.same(a, b) -- same contents
    end)
  end)

  describe('resolve', function()
    it('resolves nil to the default content', function()
      assert.are.same(content.default(), content.resolve(nil))
    end)

    it('resolves the string "intro" to the default content', function()
      assert.are.same(content.default(), content.resolve('intro'))
    end)

    it('calls a function and uses its return value', function()
      local resolved = content.resolve(function()
        return { 'one', 'two' }
      end)
      assert.are.same({ 'one', 'two' }, resolved)
    end)

    it('uses a plain list as-is', function()
      local lines = { 'a', 'b', 'c' }
      assert.are.equal(lines, content.resolve(lines))
    end)

    it('falls back to the default for an unrecognized content value', function()
      assert.are.same(content.default(), content.resolve(42))
    end)
  end)
end)

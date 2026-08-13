local highlights = require('mep.markdown.highlights')

local HEADING_GROUPS = {
  { 1, 'Title' },
  { 2, 'Function' },
  { 3, 'Keyword' },
  { 4, 'Identifier' },
  { 5, 'Type' },
  { 6, 'Comment' },
}

describe('mep.markdown.highlights', function()
  -- `:highlight clear GROUP` (not a bare nvim_set_hl(0, name, {})) is
  -- required here: once a group has been claimed via `default = true`,
  -- an explicit-but-empty nvim_set_hl still counts as "explicitly
  -- defined" and permanently blocks any later `default = true` call
  -- from reapplying — only `:hi clear` actually resets that tracking
  -- (confirmed directly; matches mep.theme.engine.apply's own use of
  -- `highlight clear` before reapplying its SPECS on every real
  -- colorscheme change). Without this, define_headers()'s own
  -- `default = true` groups only ever take effect the very first time
  -- any test happens to touch them across the whole suite.
  local function clear(name)
    vim.cmd('highlight clear ' .. name)
  end

  after_each(function()
    for _, pair in ipairs(HEADING_GROUPS) do
      clear('@markup.heading.' .. pair[1])
    end
    clear('@markup.strong')
    clear('@markup.italic')
    clear('MepMarkdownTableBorder')
    clear('MepMarkdownTableHeader')
    clear('MepMarkdownTableCell')
    clear('MepMarkdownCodeBlock')
  end)

  describe('define_headers', function()
    it('links each level to its own target group', function()
      for _, pair in ipairs(HEADING_GROUPS) do
        clear('@markup.heading.' .. pair[1])
      end
      highlights.define_headers()
      for _, pair in ipairs(HEADING_GROUPS) do
        local level, target = pair[1], pair[2]
        local hl = vim.api.nvim_get_hl(0, { name = '@markup.heading.' .. level })
        assert.are.equal(target, hl.link)
      end
    end)

    it('does not overwrite a group a user already customized (default = true)', function()
      clear('@markup.heading.1')
      vim.api.nvim_set_hl(0, '@markup.heading.1', { fg = '#123456' })
      highlights.define_headers()
      local hl = vim.api.nvim_get_hl(0, { name = '@markup.heading.1' })
      assert.are.equal('#123456', string.format('#%06x', hl.fg))
    end)
  end)

  describe('define_emphasis', function()
    it('sets @markup.strong bold and colored like Constant', function()
      clear('@markup.strong')
      highlights.define_emphasis()
      local hl = vim.api.nvim_get_hl(0, { name = '@markup.strong' })
      assert.is_true(hl.bold)
    end)

    it('sets @markup.italic italic and colored like String', function()
      clear('@markup.italic')
      highlights.define_emphasis()
      local hl = vim.api.nvim_get_hl(0, { name = '@markup.italic' })
      assert.is_true(hl.italic)
    end)

    it('always overwrites (no default), unlike define_headers', function()
      clear('@markup.strong')
      vim.api.nvim_set_hl(0, '@markup.strong', { fg = '#abcdef', bold = false })
      highlights.define_emphasis()
      local hl = vim.api.nvim_get_hl(0, { name = '@markup.strong' })
      assert.is_true(hl.bold)
    end)
  end)

  describe('define_tables', function()
    it('links border to Comment, header to @markup.strong, and cell to Normal', function()
      clear('MepMarkdownTableBorder')
      clear('MepMarkdownTableHeader')
      clear('MepMarkdownTableCell')
      highlights.define_tables()
      assert.are.equal('Comment', vim.api.nvim_get_hl(0, { name = 'MepMarkdownTableBorder' }).link)
      assert.are.equal('@markup.strong', vim.api.nvim_get_hl(0, { name = 'MepMarkdownTableHeader' }).link)
      assert.are.equal('Normal', vim.api.nvim_get_hl(0, { name = 'MepMarkdownTableCell' }).link)
    end)

    it('does not overwrite a group a user already customized (default = true)', function()
      clear('MepMarkdownTableBorder')
      vim.api.nvim_set_hl(0, 'MepMarkdownTableBorder', { fg = '#123456' })
      highlights.define_tables()
      local hl = vim.api.nvim_get_hl(0, { name = 'MepMarkdownTableBorder' })
      assert.are.equal('#123456', string.format('#%06x', hl.fg))
    end)
  end)

  describe('define_code_blocks', function()
    it('links MepMarkdownCodeBlock to CursorLine', function()
      clear('MepMarkdownCodeBlock')
      highlights.define_code_blocks()
      assert.are.equal('CursorLine', vim.api.nvim_get_hl(0, { name = 'MepMarkdownCodeBlock' }).link)
    end)

    it('does not overwrite a group a user already customized (default = true)', function()
      clear('MepMarkdownCodeBlock')
      vim.api.nvim_set_hl(0, 'MepMarkdownCodeBlock', { bg = '#123456' })
      highlights.define_code_blocks()
      local hl = vim.api.nvim_get_hl(0, { name = 'MepMarkdownCodeBlock' })
      assert.are.equal('#123456', string.format('#%06x', hl.bg))
    end)
  end)
end)

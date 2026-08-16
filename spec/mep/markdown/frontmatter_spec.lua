local frontmatter = require('mep.markdown.frontmatter')

local ns = vim.api.nvim_create_namespace('mep_markdown_frontmatter')

describe('mep.markdown.frontmatter', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    frontmatter.detach(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('region', function()
    it('finds a YAML (---) front-matter block', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'title: Hi', '---', '', '# Body' })
      local start_lnum, end_lnum = frontmatter.region(bufnr)
      assert.are.equal(1, start_lnum)
      assert.are.equal(3, end_lnum)
    end)

    it('finds a TOML (+++) front-matter block', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '+++', 'title = "Hi"', '+++', '# Body' })
      local start_lnum, end_lnum = frontmatter.region(bufnr)
      assert.are.equal(1, start_lnum)
      assert.are.equal(3, end_lnum)
    end)

    it('returns nil when line 1 is not --- or +++', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# Just a heading' })
      assert.is_nil(frontmatter.region(bufnr))
    end)

    it('returns nil for an unterminated opening delimiter', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'no closing delimiter' })
      assert.is_nil(frontmatter.region(bufnr))
    end)

    it('does not match a --- that appears later as a thematic break', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# Heading', 'para', '---', 'more' })
      assert.is_nil(frontmatter.region(bufnr))
    end)
  end)

  describe('attach/detach', function()
    it('shades the front-matter block immediately on attach', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'title: Hi', '---', '# Body' })
      frontmatter.attach(bufnr)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(3, #marks) -- one per line of the 3-line block
      assert.is_true(frontmatter.is_attached(bufnr))
    end)

    it('places no highlight when there is no front matter', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# Just a heading' })
      frontmatter.attach(bufnr)
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)

    it('detach clears the highlight and stops future updates', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'x', '---' })
      frontmatter.attach(bufnr)
      frontmatter.detach(bufnr)
      assert.is_false(frontmatter.is_attached(bufnr))
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)

    it('is idempotent — attaching twice does not double the extmarks', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'x', '---' })
      frontmatter.attach(bufnr)
      frontmatter.attach(bufnr)
      assert.are.equal(3, #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)
  end)

  describe('_reset', function()
    it('detaches every tracked buffer', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '---', 'x', '---' })
      frontmatter.attach(bufnr)
      frontmatter._reset()
      assert.is_false(frontmatter.is_attached(bufnr))
    end)
  end)
end)

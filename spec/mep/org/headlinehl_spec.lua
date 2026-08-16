local headlinehl = require('mep.org.headlinehl')

local NS = vim.api.nvim_create_namespace('mep_org_headline')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

describe('mep.org.headlinehl', function()
  describe('apply', function()
    it('colors a level-1 headline with the first group', function()
      local buf = make_buf({ '* Level one' })
      headlinehl.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(0, marks[1][2]) -- 0-indexed row for line 1
      assert.are.equal(headlinehl.hl_groups[1], marks[1][4].hl_group)
    end)

    it('gives each level its own group', function()
      local buf = make_buf({
        '* one',
        '** two',
        '*** three',
        '**** four',
        '***** five',
        '****** six',
      })
      headlinehl.apply(buf)
      local marks = extmarks(buf)
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)
      for i, mark in ipairs(marks) do
        assert.are.equal(headlinehl.hl_groups[i], mark[4].hl_group)
      end
    end)

    it('cycles back to the first group past the last configured level', function()
      local buf = make_buf({ string.rep('*', #headlinehl.hl_groups + 1) .. ' seven' })
      headlinehl.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(headlinehl.hl_groups[1], marks[1][4].hl_group)
    end)

    it('does not mark lines that are not headlines', function()
      local buf = make_buf({ 'plain text', '  * not a headline (indented)', '*no space after stars' })
      headlinehl.apply(buf)
      assert.are.same({}, extmarks(buf))
    end)

    it('clears previous marks before recomputing', function()
      local buf = make_buf({ '* one' })
      headlinehl.apply(buf)
      headlinehl.apply(buf)
      assert.are.equal(1, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes every mark this module set', function()
      local buf = make_buf({ '* one' })
      headlinehl.apply(buf)
      headlinehl.clear(buf)
      assert.are.same({}, extmarks(buf))
    end)
  end)

  describe('define_default_hl', function()
    it('links each MepOrgHeadlineN group to its configured target', function()
      headlinehl.define_default_hl()
      for i, group in ipairs(headlinehl.hl_groups) do
        local hl = vim.api.nvim_get_hl(0, { name = group })
        assert.are.equal(headlinehl.LINKS[i], hl.link)
      end
    end)

    it('picks blue for the first level', function()
      headlinehl.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = headlinehl.hl_groups[1] })
      assert.are.equal('Function', hl.link) -- Function is fg=blue in every mep.theme palette
    end)

    it('never links to Constant, to stay distinct from MepOrgResultsBlock', function()
      headlinehl.define_default_hl()
      for _, link in ipairs(headlinehl.LINKS) do
        assert.are_not.equal('Constant', link)
      end
    end)
  end)
end)

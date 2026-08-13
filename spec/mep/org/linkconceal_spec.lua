local linkconceal = require('mep.org.linkconceal')

local NS = vim.api.nvim_create_namespace('mep_org_link_conceal')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

describe('mep.org.linkconceal', function()
  describe('apply', function()
    it('conceals the two bracket pairs of a bare link, leaving the target visible', function()
      local buf = make_buf({ '[[https://example.com]]' })
      linkconceal.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(2, #marks)

      -- opening "[["
      table.sort(marks, function(a, b)
        return a[3] < b[3]
      end)
      local open_mark, close_mark = marks[1], marks[2]
      assert.are.equal(0, open_mark[3]) -- start col
      assert.are.equal(2, open_mark[4].end_col)
      assert.are.equal('', open_mark[4].conceal)

      local line = '[[https://example.com]]'
      assert.are.equal(#line - 2, close_mark[3])
      assert.are.equal(#line, close_mark[4].end_col)
      assert.are.equal('', close_mark[4].conceal)
    end)

    it('conceals "[[target][" and "]]" for a link with a description, leaving only the description', function()
      local line = '[[https://example.com][Example]]'
      local buf = make_buf({ line })
      linkconceal.apply(buf)
      local marks = extmarks(buf)
      table.sort(marks, function(a, b)
        return a[3] < b[3]
      end)
      assert.are.equal(2, #marks)

      local head_mark, tail_mark = marks[1], marks[2]
      assert.are.equal(0, head_mark[3])
      -- "[[https://example.com][" is 24 chars, description "Example" starts right after
      local desc_start = line:find('Example', 1, true) - 1 -- 0-based
      assert.are.equal(desc_start, head_mark[4].end_col)

      assert.are.equal(#line - 2, tail_mark[3])
      assert.are.equal(#line, tail_mark[4].end_col)
    end)

    it('conceals every link on a line with multiple links', function()
      local buf = make_buf({ '[[a]] and [[b][B]]' })
      linkconceal.apply(buf)
      assert.are.equal(4, #extmarks(buf)) -- 2 marks per link x 2 links
    end)

    it('conceals links across multiple lines', function()
      local buf = make_buf({ '[[a]]', 'plain', '[[b]]' })
      linkconceal.apply(buf)
      local marks = extmarks(buf)
      local rows = {}
      for _, m in ipairs(marks) do
        rows[m[2]] = true
      end
      assert.is_true(rows[0])
      assert.is_true(rows[2])
      assert.is_nil(rows[1])
    end)

    it('sets no extmarks for a buffer with no links', function()
      local buf = make_buf({ 'plain text', 'more text' })
      linkconceal.apply(buf)
      assert.are.equal(0, #extmarks(buf))
    end)

    it('clears previous extmarks before reapplying (does not accumulate)', function()
      local buf = make_buf({ '[[a]]' })
      linkconceal.apply(buf)
      linkconceal.apply(buf)
      linkconceal.apply(buf)
      assert.are.equal(2, #extmarks(buf))
    end)

    it('reflects buffer edits on reapplication', function()
      local buf = make_buf({ '[[a]]' })
      linkconceal.apply(buf)
      assert.are.equal(2, #extmarks(buf))
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'no link anymore' })
      linkconceal.apply(buf)
      assert.are.equal(0, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes all concealment extmarks without reapplying', function()
      local buf = make_buf({ '[[a]]' })
      linkconceal.apply(buf)
      assert.are.equal(2, #extmarks(buf))
      linkconceal.clear(buf)
      assert.are.equal(0, #extmarks(buf))
    end)
  end)
end)

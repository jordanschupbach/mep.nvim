local blockhl = require('mep.org.blockhl')

local NS = vim.api.nvim_create_namespace('mep_org_src_block_bg')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

describe('mep.org.blockhl', function()
  describe('apply', function()
    it('covers every line of a src block, including its delimiters', function()
      local buf = make_buf({
        'before',
        '#+begin_src lua',
        'print(1)',
        '#+end_src',
        'after',
      })
      blockhl.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(3, #marks)
      local rows = {}
      for _, m in ipairs(marks) do
        rows[#rows + 1] = m[2]
      end
      table.sort(rows)
      assert.are.same({ 1, 2, 3 }, rows) -- 0-indexed rows for lines 2-4

      for _, m in ipairs(marks) do
        assert.are.equal(blockhl.hl_group, m[4].hl_group)
        assert.is_true(m[4].hl_eol)
      end
    end)

    it('does not mark lines outside any src block', function()
      local buf = make_buf({ 'plain text', 'more plain text' })
      blockhl.apply(buf)
      assert.are.same({}, extmarks(buf))
    end)

    it('marks multiple blocks independently', function()
      local buf = make_buf({
        '#+begin_src lua', 'a', '#+end_src',
        '#+begin_src python', 'b', '#+end_src',
      })
      blockhl.apply(buf)
      assert.are.equal(6, #extmarks(buf))
    end)

    it('clears previous marks before recomputing', function()
      local buf = make_buf({ '#+begin_src lua', 'a', '#+end_src' })
      blockhl.apply(buf)
      blockhl.apply(buf)
      assert.are.equal(3, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes every mark this module set', function()
      local buf = make_buf({ '#+begin_src lua', 'a', '#+end_src' })
      blockhl.apply(buf)
      blockhl.clear(buf)
      assert.are.same({}, extmarks(buf))
    end)
  end)

  describe('define_default_hl', function()
    it('links MepOrgSrcBlock to CursorLine', function()
      blockhl.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = blockhl.hl_group })
      assert.are.equal('CursorLine', hl.link)
    end)
  end)
end)

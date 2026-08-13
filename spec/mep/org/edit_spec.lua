local edit = require('mep.org.edit')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.edit', function()
  describe('insert_headline', function()
    it('inserts an empty same-level sibling after the subtree end', function()
      local buf = make_buf({
        '* Heading 1',
        'body',
        '** Sub 1.1',
        '* Heading 2',
      })
      local new_lnum = edit.insert_headline(buf, 1)
      assert.are.equal(4, new_lnum)
      assert.are.equal('* ', vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1])
      assert.are.equal('* Heading 2', vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1])
    end)

    it('inserts right after a single-line subtree with no body', function()
      local buf = make_buf({ '* Only heading' })
      local new_lnum = edit.insert_headline(buf, 1)
      assert.are.equal(2, new_lnum)
      assert.are.equal('* ', vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1])
    end)

    it('matches the level of a deeper headline, not the top-level default', function()
      local buf = make_buf({ '* Top', '** Sub' })
      local new_lnum = edit.insert_headline(buf, 2)
      assert.are.equal('** ', vim.api.nvim_buf_get_lines(buf, new_lnum - 1, new_lnum, false)[1])
    end)

    it('returns nil when lnum is not inside any headline', function()
      local buf = make_buf({ 'no headline here' })
      assert.is_nil(edit.insert_headline(buf, 1))
    end)
  end)

  describe('insert_todo_headline', function()
    it('pre-fills the first configured TODO keyword', function()
      local buf = make_buf({ '* Heading' })
      local new_lnum = edit.insert_todo_headline(buf, 1, { 'TODO', 'DONE' })
      assert.are.equal('* TODO ', vim.api.nvim_buf_get_lines(buf, new_lnum - 1, new_lnum, false)[1])
    end)

    it('falls back to a plain headline with no todo_keywords', function()
      local buf = make_buf({ '* Heading' })
      local new_lnum = edit.insert_todo_headline(buf, 1, nil)
      assert.are.equal('* ', vim.api.nvim_buf_get_lines(buf, new_lnum - 1, new_lnum, false)[1])
    end)
  end)
end)

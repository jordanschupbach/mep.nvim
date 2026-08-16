local checkbox = require('mep.markdown.checkbox')

describe('mep.markdown.checkbox', function()
  describe('is_checkbox', function()
    it('is true for a dash-bullet checkbox', function()
      assert.is_true(checkbox.is_checkbox('- [ ] task'))
      assert.is_true(checkbox.is_checkbox('- [x] task'))
      assert.is_true(checkbox.is_checkbox('- [X] task'))
    end)

    it('is true for +/* bullet markers', function()
      assert.is_true(checkbox.is_checkbox('+ [ ] task'))
      assert.is_true(checkbox.is_checkbox('* [ ] task'))
    end)

    it('is true for a numbered-list checkbox', function()
      assert.is_true(checkbox.is_checkbox('1. [ ] task'))
      assert.is_true(checkbox.is_checkbox('2) [x] task'))
    end)

    it('is true with leading indentation', function()
      assert.is_true(checkbox.is_checkbox('  - [ ] nested task'))
    end)

    it('is false for a plain list item', function()
      assert.is_false(checkbox.is_checkbox('- just a bullet'))
    end)

    it('is false for a checkbox-looking but malformed line', function()
      assert.is_false(checkbox.is_checkbox('-[ ] no space after dash'))
    end)
  end)

  describe('is_checked', function()
    it('is false for an unchecked box', function()
      assert.is_false(checkbox.is_checked('- [ ] task'))
    end)

    it('is true for a checked box (lower or upper x)', function()
      assert.is_true(checkbox.is_checked('- [x] task'))
      assert.is_true(checkbox.is_checked('- [X] task'))
    end)

    it('returns nil for a non-checkbox line', function()
      assert.is_nil(checkbox.is_checked('not a checkbox'))
    end)
  end)

  describe('toggle', function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('checks an unchecked box, returning true', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '- [ ] task' })
      local result = checkbox.toggle(bufnr, 1)
      assert.is_true(result)
      assert.are.same({ '- [x] task' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('unchecks a checked box, returning false', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '- [X] task' })
      local result = checkbox.toggle(bufnr, 1)
      assert.is_false(result)
      assert.are.same({ '- [ ] task' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('preserves indentation and trailing text', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '  - [ ] a nested task with text' })
      checkbox.toggle(bufnr, 1)
      assert.are.same({ '  - [x] a nested task with text' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('returns nil and does nothing for a non-checkbox line', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'plain text' })
      local result = checkbox.toggle(bufnr, 1)
      assert.is_nil(result)
      assert.are.same({ 'plain text' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)
  end)
end)

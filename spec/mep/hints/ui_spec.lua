local ui = require('mep.hints.ui')

local ns = vim.api.nvim_create_namespace('mep_hints')

describe('mep.hints.ui', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo bar baz' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('show', function()
    it('sets one match extmark and one label overlay per target', function()
      ui.show(bufnr, {
        { lnum = 1, col = 0, len = 3, label = 'a' },
        { lnum = 1, col = 4, len = 3, label = 'b' },
      })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.are.equal(4, #marks) -- 2 targets * (match + label)
    end)

    it('overlays the label text at the target column', function()
      ui.show(bufnr, { { lnum = 1, col = 0, len = 3, label = 'x' } })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      local found_label = false
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_text then
          assert.are.equal('x', details.virt_text[1][1])
          assert.are.equal('MepHintLabel', details.virt_text[1][2])
          found_label = true
        end
      end
      assert.is_true(found_label)
    end)

    it('clears any previously shown targets before rendering new ones', function()
      ui.show(bufnr, { { lnum = 1, col = 0, len = 3, label = 'a' } })
      ui.show(bufnr, { { lnum = 1, col = 4, len = 3, label = 'b' } })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(2, #marks) -- only the second call's target
    end)

    it('skips targets outside the buffer current line count', function()
      ui.show(bufnr, { { lnum = 99, col = 0, len = 1, label = 'a' } })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)
  end)

  describe('clear', function()
    it('removes every extmark this module set', function()
      ui.show(bufnr, { { lnum = 1, col = 0, len = 3, label = 'a' } })
      ui.clear(bufnr)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)

    it('is a no-op on an invalid buffer', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(scratch, { force = true })
      assert.has_no.errors(function()
        ui.clear(scratch)
      end)
    end)
  end)

  describe('define_default_hl', function()
    it('defines MepHintMatch/MepHintLabel', function()
      ui.define_default_hl()
      assert.is_true(vim.fn.hlexists('MepHintMatch') == 1)
      assert.is_true(vim.fn.hlexists('MepHintLabel') == 1)
    end)
  end)
end)

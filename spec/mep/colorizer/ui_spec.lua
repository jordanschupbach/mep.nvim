local ui = require('mep.colorizer.ui')

local ns = vim.api.nvim_create_namespace('mep_colorizer')

describe('mep.colorizer.ui', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('bg_group/fg_group', function()
    it('names a background group after the hex, without the #', function()
      assert.are.equal('MepColorizerBg_ff0000', ui.bg_group('#ff0000'))
    end)

    it('names a foreground group after the hex, without the #', function()
      assert.are.equal('MepColorizerFg_ff0000', ui.fg_group('#ff0000'))
    end)

    it('defines a real highlight group with bg set and a readable fg', function()
      ui.bg_group('#000000')
      local hl = vim.api.nvim_get_hl(0, { name = 'MepColorizerBg_000000' })
      assert.are.equal(0x000000, hl.bg)
      assert.are.equal(0xffffff, hl.fg) -- white text over a black background
    end)

    it('picks black text over a light background', function()
      ui.bg_group('#ffffff')
      local hl = vim.api.nvim_get_hl(0, { name = 'MepColorizerBg_ffffff' })
      assert.are.equal(0x000000, hl.fg)
    end)
  end)

  describe('render (mode = background)', function()
    it('places one highlighted extmark per match, spanning the match', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'color: #ff0000;' })
      ui.render(bufnr, 'background', '●')
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      assert.are.equal('MepColorizerBg_ff0000', marks[1][4].hl_group)
      assert.are.equal(7, marks[1][3]) -- 0-indexed start col
      assert.are.equal(14, marks[1][4].end_col)
    end)

    it('clears previous matches before re-rendering', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '#ff0000' })
      ui.render(bufnr, 'background', '●')
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'no colors' })
      ui.render(bufnr, 'background', '●')
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)
  end)

  describe('render (mode = swatch)', function()
    it('places an inline virtual-text swatch before the match', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'color: #ff0000;' })
      ui.render(bufnr, 'swatch', '●')
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      local details = marks[1][4]
      assert.are.equal('●', details.virt_text[1][1])
      assert.are.equal('MepColorizerFg_ff0000', details.virt_text[1][2])
    end)
  end)

  describe('clear', function()
    it('removes every extmark this module set', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '#ff0000' })
      ui.render(bufnr, 'background', '●')
      ui.clear(bufnr)
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)

    it('is a no-op on an invalid buffer', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(scratch, { force = true })
      assert.has_no.errors(function()
        ui.clear(scratch)
      end)
    end)
  end)
end)

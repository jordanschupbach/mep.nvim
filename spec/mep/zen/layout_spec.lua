-- Real vsplit windows (no floats) — mep.zen.layout deliberately doesn't
-- use mep.sidebar's own float-based isolation (see its own header
-- comment), so these tests build/tear down real tabpage layout instead.
local layout = require('mep.zen.layout')

describe('mep.zen.layout', function()
  local win

  before_each(function()
    pcall(vim.cmd, 'only')
    win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    pcall(vim.cmd, 'only')
  end)

  describe('center', function()
    it('adds a blank padding window on each side, sized to split the remainder', function()
      -- minimal_init.lua sets columns = 120; width 90 -> 15 columns pad
      -- on each side.
      local padding = layout.center(win, 90)
      assert.is_not_nil(padding)
      assert.are.equal(15, vim.api.nvim_win_get_width(padding.left_win))
      assert.are.equal(15, vim.api.nvim_win_get_width(padding.right_win))
    end)

    it('leaves focus on the original window', function()
      layout.center(win, 90)
      assert.are.equal(win, vim.api.nvim_get_current_win())
    end)

    it('does not touch the original buffer', function()
      local buf = vim.api.nvim_win_get_buf(win)
      layout.center(win, 90)
      assert.are.equal(buf, vim.api.nvim_win_get_buf(win))
    end)

    it('padding windows hold scratch buffers with no gutter', function()
      local padding = layout.center(win, 90)
      local pad_buf = vim.api.nvim_win_get_buf(padding.left_win)
      assert.are.equal('nofile', vim.bo[pad_buf].buftype)
      assert.is_false(vim.wo[padding.left_win].number)
      assert.are.equal('no', vim.wo[padding.left_win].signcolumn)
    end)

    it('padding windows are winfixwidth, so later splits elsewhere leave them alone', function()
      local padding = layout.center(win, 90)
      assert.is_true(vim.wo[padding.left_win].winfixwidth)
      assert.is_true(vim.wo[padding.right_win].winfixwidth)
    end)

    it('returns nil when the window is already narrower than the target width', function()
      assert.is_nil(layout.center(win, 100000))
    end)
  end)

  describe('uncenter', function()
    it('closes both padding windows', function()
      local padding = layout.center(win, 90)
      layout.uncenter(padding)
      assert.is_false(vim.api.nvim_win_is_valid(padding.left_win))
      assert.is_false(vim.api.nvim_win_is_valid(padding.right_win))
    end)

    it('is a no-op given nil', function()
      assert.has_no.errors(function()
        layout.uncenter(nil)
      end)
    end)

    it('tolerates a padding window already closed some other way', function()
      local padding = layout.center(win, 90)
      vim.api.nvim_win_close(padding.left_win, true)
      assert.has_no.errors(function()
        layout.uncenter(padding)
      end)
      assert.is_false(vim.api.nvim_win_is_valid(padding.right_win))
    end)
  end)
end)

local gutter = require('mep.zen.gutter')

describe('mep.zen.gutter', function()
  local win

  before_each(function()
    local buf = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
  end)

  after_each(function()
    pcall(vim.api.nvim_win_close, win, true)
  end)

  describe('suppress', function()
    it('turns off number, relativenumber, and the sign column', function()
      gutter.suppress(win)
      assert.is_false(vim.wo[win].number)
      assert.is_false(vim.wo[win].relativenumber)
      assert.are.equal('no', vim.wo[win].signcolumn)
    end)

    it('returns the previous values', function()
      vim.wo[win].number = true
      vim.wo[win].signcolumn = 'yes'
      local saved = gutter.suppress(win)
      assert.is_true(saved.number)
      assert.are.equal('yes', saved.signcolumn)
    end)
  end)

  describe('restore', function()
    it('puts the previous values back', function()
      vim.wo[win].number = true
      vim.wo[win].signcolumn = 'yes'
      local saved = gutter.suppress(win)
      assert.is_false(vim.wo[win].number)

      gutter.restore(win, saved)
      assert.is_true(vim.wo[win].number)
      assert.are.equal('yes', vim.wo[win].signcolumn)
    end)

    it('is a no-op on an already-closed window', function()
      local saved = gutter.suppress(win)
      vim.api.nvim_win_close(win, true)
      assert.has_no.errors(function()
        gutter.restore(win, saved)
      end)
    end)
  end)
end)

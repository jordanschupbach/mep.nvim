local targets = require('mep.hints.targets')

describe('mep.hints.targets', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('word_starts', function()
    it('finds every word start on a line', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo bar-baz qux' })
      local result = targets.word_starts(bufnr, 1, 1)
      assert.are.same({
        { lnum = 1, col = 0, len = 3 }, -- foo
        { lnum = 1, col = 4, len = 3 }, -- bar
        { lnum = 1, col = 8, len = 3 }, -- baz
        { lnum = 1, col = 12, len = 3 }, -- qux
      }, result)
    end)

    it('treats underscores as word characters', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'snake_case' })
      local result = targets.word_starts(bufnr, 1, 1)
      assert.are.same({ { lnum = 1, col = 0, len = 10 } }, result)
    end)

    it('spans multiple lines, only within the given range', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
      local result = targets.word_starts(bufnr, 2, 3)
      assert.are.same({
        { lnum = 2, col = 0, len = 3 },
        { lnum = 3, col = 0, len = 5 },
      }, result)
    end)

    it('returns an empty list for a line with no word characters', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '   ---   ' })
      assert.are.same({}, targets.word_starts(bufnr, 1, 1))
    end)
  end)

  describe('char_matches', function()
    it('finds every occurrence of the given character', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'abcabc' })
      local result = targets.char_matches(bufnr, 1, 1, 'a')
      assert.are.same({
        { lnum = 1, col = 0, len = 1 },
        { lnum = 1, col = 3, len = 1 },
      }, result)
    end)

    it('matches Lua-pattern-special characters literally', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a.b.c' })
      local result = targets.char_matches(bufnr, 1, 1, '.')
      assert.are.same({
        { lnum = 1, col = 1, len = 1 },
        { lnum = 1, col = 3, len = 1 },
      }, result)
    end)

    it('returns an empty list for a nil or empty character', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'abc' })
      assert.are.same({}, targets.char_matches(bufnr, 1, 1, nil))
      assert.are.same({}, targets.char_matches(bufnr, 1, 1, ''))
    end)

    it('returns an empty list when there are no matches', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'abc' })
      assert.are.same({}, targets.char_matches(bufnr, 1, 1, 'z'))
    end)
  end)

  describe('visible_range', function()
    it('reports the current window when lines fit entirely on screen', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
      local win = vim.api.nvim_open_win(bufnr, false, {
        relative = 'editor',
        row = 0,
        col = 0,
        width = 20,
        height = 10,
      })
      local first, last = targets.visible_range(win)
      assert.are.equal(1, first)
      assert.are.equal(3, last)
      vim.api.nvim_win_close(win, true)
    end)
  end)
end)

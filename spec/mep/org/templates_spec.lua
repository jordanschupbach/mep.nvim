local templates = require('mep.org.templates')

local function make_win(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = 20,
    height = 10,
  })
  return buf, win
end

describe('mep.org.templates', function()
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  -- Cursor placed one-past-the-end of the typed trigger text; nvim_win_set_cursor
  -- clamps to the last valid character in normal-mode buffer state, so the
  -- cursor must be positioned while the buffer is in insert mode to land
  -- exactly after "<s" the way real typing would.
  local function set_cursor_after(win, lnum, col)
    vim.cmd('startinsert')
    vim.api.nvim_win_set_cursor(win, { lnum, col })
    vim.cmd('stopinsert')
  end

  describe('expand_at_cursor', function()
    it('expands a known trigger into a begin/end block', function()
      local buf, win = make_win({ '<s' })
      set_cursor_after(win, 1, 2)
      local expanded = templates.expand_at_cursor(buf, win)
      assert.is_true(expanded)
      assert.are.same({ '#+begin_src', '', '#+end_src' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('preserves leading indentation', function()
      local buf, win = make_win({ '    <q' })
      set_cursor_after(win, 1, 6)
      templates.expand_at_cursor(buf, win)
      assert.are.same({
        '    #+begin_quote',
        '    ',
        '    #+end_quote',
      }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('leaves the cursor on the blank line between the markers', function()
      local buf, win = make_win({ '<e' })
      set_cursor_after(win, 1, 2)
      templates.expand_at_cursor(buf, win)
      assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('preserves trailing text after the cursor', function()
      local buf, win = make_win({ '<crest' })
      set_cursor_after(win, 1, 2)
      templates.expand_at_cursor(buf, win)
      assert.are.same({ '#+begin_center', '', '#+end_centerrest' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('does nothing and returns false for an unknown trigger key', function()
      local buf, win = make_win({ '<z' })
      set_cursor_after(win, 1, 2)
      local expanded = templates.expand_at_cursor(buf, win)
      assert.is_false(expanded)
      assert.are.same({ '<z' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('does nothing when the text before the cursor does not match the trigger pattern', function()
      local buf, win = make_win({ 'plain text' })
      set_cursor_after(win, 1, 10)
      assert.is_false(templates.expand_at_cursor(buf, win))
    end)

    it('does not match when the cursor is not immediately after the key', function()
      local buf, win = make_win({ '<s extra' })
      set_cursor_after(win, 1, 8)
      assert.is_false(templates.expand_at_cursor(buf, win))
    end)
  end)

  describe('templates table', function()
    it('maps every documented trigger key to a block name', function()
      assert.are.same({
        s = 'src',
        e = 'example',
        q = 'quote',
        c = 'center',
        v = 'verse',
        C = 'comment',
      }, templates.templates)
    end)
  end)
end)

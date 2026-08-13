local list = require('mep.org.list')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.list', function()
  describe('parse', function()
    it('parses a dash bullet', function()
      local item = list.parse('- buy milk')
      assert.are.equal('bullet', item.kind)
      assert.are.equal('-', item.marker)
      assert.are.equal('', item.indent)
      assert.are.equal('buy milk', item.content)
    end)

    it('parses a plus bullet', function()
      local item = list.parse('+ buy milk')
      assert.are.equal('+', item.marker)
    end)

    it('parses an indented star bullet', function()
      local item = list.parse('  * buy milk')
      assert.are.equal('bullet', item.kind)
      assert.are.equal('*', item.marker)
      assert.are.equal('  ', item.indent)
    end)

    it('rejects a column-0 star (that is a headline, not a list item)', function()
      assert.is_nil(list.parse('* buy milk'))
    end)

    it('parses an ordered item with a dot separator', function()
      local item = list.parse('1. first')
      assert.are.equal('ordered', item.kind)
      assert.are.equal(1, item.number)
      assert.are.equal('.', item.sep)
      assert.are.equal('first', item.content)
    end)

    it('parses an ordered item with a paren separator', function()
      local item = list.parse('12) twelfth')
      assert.are.equal(12, item.number)
      assert.are.equal(')', item.sep)
    end)

    it('parses indentation on an ordered item', function()
      local item = list.parse('    3. nested')
      assert.are.equal('    ', item.indent)
    end)

    it('returns nil for a non-list line', function()
      assert.is_nil(list.parse('just a plain line'))
      assert.is_nil(list.parse(''))
    end)

    it('returns nil for a headline', function()
      assert.is_nil(list.parse('* TODO Task'))
    end)
  end)

  describe('is_list_item', function()
    it('mirrors parse', function()
      assert.is_true(list.is_list_item('- item'))
      assert.is_false(list.is_list_item('not a list'))
    end)
  end)

  describe('renumber', function()
    it('renumbers a contiguous ordered run from 1', function()
      local buf = make_buf({ '1. a', '5. b', '9. c' })
      local n = list.renumber(buf, 1)
      assert.are.equal(3, n)
      assert.are.same({ '1. a', '2. b', '3. c' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('preserves each item`s separator style', function()
      local buf = make_buf({ '1) a', '3) b' })
      list.renumber(buf, 1)
      assert.are.same({ '1) a', '2) b' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('works from any item in the run, not just the first', function()
      local buf = make_buf({ '1. a', '5. b', '9. c' })
      list.renumber(buf, 3)
      assert.are.same({ '1. a', '2. b', '3. c' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('only renumbers items at the same indent', function()
      local buf = make_buf({ '1. a', '  1. nested', '2. b' })
      local n = list.renumber(buf, 1)
      assert.are.equal(2, n)
      assert.are.same({ '1. a', '  1. nested', '2. b' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('stops at a bullet item breaking the ordered run', function()
      local buf = make_buf({ '1. a', '2. b', '- bullet', '9. c' })
      local n = list.renumber(buf, 1)
      assert.are.equal(2, n)
    end)

    it('returns nil for a bullet item', function()
      local buf = make_buf({ '- a' })
      assert.is_nil(list.renumber(buf, 1))
    end)

    it('returns nil for a non-list line', function()
      local buf = make_buf({ 'plain' })
      assert.is_nil(list.renumber(buf, 1))
    end)
  end)

  describe('indent_item / outdent_item', function()
    it('indents a single item by 2 spaces', function()
      local buf = make_buf({ '- item' })
      local n = list.indent_item(buf, 1)
      assert.are.equal(1, n)
      assert.are.equal('  - item', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('indents an item together with its more-indented continuation lines', function()
      local buf = make_buf({ '- item', '  continuation', '  - nested', '- sibling' })
      local n = list.indent_item(buf, 1)
      assert.are.equal(3, n)
      assert.are.same({
        '  - item',
        '    continuation',
        '    - nested',
        '- sibling',
      }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('stops at a blank line', function()
      local buf = make_buf({ '- item', '  continuation', '', '  orphaned' })
      local n = list.indent_item(buf, 1)
      assert.are.equal(2, n)
      assert.are.same({ '  - item', '    continuation', '', '  orphaned' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('outdents a single item', function()
      local buf = make_buf({ '  - item' })
      local n = list.outdent_item(buf, 1)
      assert.are.equal(1, n)
      assert.are.equal('- item', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('refuses to outdent an item already at column 0', function()
      local buf = make_buf({ '- item' })
      assert.is_nil(list.outdent_item(buf, 1))
      assert.are.equal('- item', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it('returns nil for a non-list line', function()
      local buf = make_buf({ 'plain' })
      assert.is_nil(list.indent_item(buf, 1))
    end)
  end)

  describe('continue_at_cursor', function()
    local function make_win(lines)
      local buf = make_buf(lines)
      local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
      return buf, win
    end

    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    it('continues a bullet list at end of line', function()
      local buf, win = make_win({ '- first' })
      -- continue_at_cursor is only ever invoked from the insert-mode
      -- <CR> keymap in real usage, so it lands the cursor one-past-the-
      -- end of the fresh marker; nvim_win_set_cursor only allows that in
      -- insert-mode buffer state (normal mode clamps to the last valid
      -- char), so this test must be in insert mode too to observe it.
      vim.api.nvim_set_current_win(win)
      vim.cmd('startinsert')
      local ok = list.continue_at_cursor(buf, win, 1, 7) -- end of "- first"
      vim.cmd('stopinsert')
      assert.is_true(ok)
      assert.are.same({ '- first', '- ' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.same({ 2, 2 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('continues an ordered list with the next number and renumbers the run', function()
      local buf, win = make_win({ '1. first', '2. second' })
      list.continue_at_cursor(buf, win, 1, 8) -- end of "1. first"
      assert.are.same({ '1. first', '2. ', '3. second' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('splits text after the cursor onto the new item', function()
      local buf, win = make_win({ '- hello world' })
      list.continue_at_cursor(buf, win, 1, 7) -- right after "hello"
      assert.are.same({ '- hello', '-  world' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('continues a checkbox item with a fresh unchecked box', function()
      local buf, win = make_win({ '- [X] done item' })
      list.continue_at_cursor(buf, win, 1, 15)
      assert.are.same({ '- [X] done item', '- [ ] ' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('exits the list on an empty bullet item', function()
      local buf, win = make_win({ '- ' })
      local ok = list.continue_at_cursor(buf, win, 1, 2)
      assert.is_true(ok)
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('exits the list on an empty checkbox item', function()
      local buf, win = make_win({ '- [ ] ' })
      local ok = list.continue_at_cursor(buf, win, 1, 6)
      assert.is_true(ok)
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('returns false and does nothing for a non-list line', function()
      local buf, win = make_win({ 'plain text' })
      local ok = list.continue_at_cursor(buf, win, 1, 10)
      assert.is_false(ok)
      assert.are.same({ 'plain text' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)
end)

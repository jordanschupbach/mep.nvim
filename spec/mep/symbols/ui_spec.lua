local ui = require('mep.symbols.ui')

describe('mep.symbols.ui', function()
  describe('create_window / close_window', function()
    it('creates a scratch buffer in a real (non-floating) split of the given width', function()
      local buf, win = ui.create_window(25, 'right')

      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.are.equal('wipe', vim.bo[buf].bufhidden)
      assert.are.equal('mep-symbols', vim.bo[buf].filetype)
      assert.are.equal(25, vim.api.nvim_win_get_width(win))

      ui.close_window(win)
    end)

    it('splits the *current* window, not the whole tabpage', function()
      vim.cmd('only')
      local target_win = vim.api.nvim_get_current_win()
      local win_count_before = #vim.api.nvim_list_wins()

      local _, win = ui.create_window(20, 'right')

      -- Exactly one extra window: the original current window plus the
      -- new outline split, nothing else pulled into it.
      assert.are.equal(win_count_before + 1, #vim.api.nvim_list_wins())
      assert.is_true(vim.api.nvim_win_is_valid(target_win))
      ui.close_window(win)
    end)

    it('defaults to the right side when position is unrecognized', function()
      local _, win = ui.create_window(20, 'bogus')
      assert.is_true(vim.api.nvim_win_is_valid(win))
      ui.close_window(win)
    end)

    it('sets window-local display options suited to an outline panel', function()
      local _, win = ui.create_window(25, 'right')
      assert.is_false(vim.wo[win].number)
      assert.is_false(vim.wo[win].wrap)
      assert.is_true(vim.wo[win].cursorline)
      assert.are.equal('no', vim.wo[win].signcolumn)
      assert.is_true(vim.wo[win].winfixwidth)
      ui.close_window(win)
    end)

    it('close_window invalidates the window and is safe to call twice', function()
      local _, win = ui.create_window(25, 'right')
      ui.close_window(win)
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.has_no.errors(function()
        ui.close_window(win)
      end)
    end)

    it('close_window(nil) does not error', function()
      assert.has_no.errors(function()
        ui.close_window(nil)
      end)
    end)
  end)

  describe('render', function()
    local buf, win

    before_each(function()
      buf, win = ui.create_window(30, 'right')
    end)

    after_each(function()
      ui.close_window(win)
    end)

    it('renders one line per symbol, indented by depth, as [Kind] name', function()
      local symbols = {
        { name = 'Foo', kind_name = 'Class', depth = 0, lnum = 1, col = 0 },
        { name = 'bar', kind_name = 'Method', depth = 1, lnum = 2, col = 2 },
      }
      local activatable = ui.render(buf, symbols, nil)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.matches('%[Class%] Foo', lines[1])
      assert.matches('%[Method%] bar', lines[2])
      assert.is_true(#(lines[2]:match('^%s*')) > #(lines[1]:match('^%s*')))

      assert.are.same(symbols[1], activatable[1])
      assert.are.same(symbols[2], activatable[2])
    end)

    it('shows a message line instead of symbols when err is given', function()
      local activatable = ui.render(buf, nil, 'no client attached')
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ 'no client attached' }, lines)
      assert.are.same({}, activatable)
    end)

    it('shows a "no symbols" message for a nil symbol list with no error', function()
      local activatable = ui.render(buf, nil, nil)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ 'No symbols' }, lines)
      assert.are.same({}, activatable)
    end)

    it('shows a "no symbols" message for an empty symbol list', function()
      local activatable = ui.render(buf, {}, nil)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ 'No symbols' }, lines)
      assert.are.same({}, activatable)
    end)

    it('highlights the kind tag on every symbol line', function()
      local symbols = {
        { name = 'Foo', kind_name = 'Class', depth = 0, lnum = 1, col = 0 },
        { name = 'bar', kind_name = 'Method', depth = 0, lnum = 2, col = 0 },
      }
      ui.render(buf, symbols, nil)

      local ns = vim.api.nvim_get_namespaces()['mep_symbols_kind']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(2, #marks)
    end)

    it('leaves the buffer unmodifiable after rendering', function()
      ui.render(buf, {}, nil)
      assert.is_false(vim.bo[buf].modifiable)
    end)

    it('clears previous highlights when re-rendering with fewer symbols', function()
      ui.render(buf, {
        { name = 'a', kind_name = 'Class', depth = 0, lnum = 1, col = 0 },
        { name = 'b', kind_name = 'Class', depth = 0, lnum = 2, col = 0 },
      }, nil)
      ui.render(buf, { { name = 'a', kind_name = 'Class', depth = 0, lnum = 1, col = 0 } }, nil)

      local ns = vim.api.nvim_get_namespaces()['mep_symbols_kind']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
    end)

    it('returns an empty activatable table for an invalid buffer', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(scratch, { force = true })
      assert.are.same({}, ui.render(scratch, {}, nil))
    end)
  end)
end)

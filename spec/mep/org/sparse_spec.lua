local sparse = require('mep.org.sparse')

local function make_win(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 10 })
  return buf, win
end

local function foldclosed_in(win, lnum)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.foldclosed(lnum)
  end)
end

describe('mep.org.sparse', function()
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  local SAMPLE = {
    '* Grandparent', -- 1
    '** Parent A', -- 2
    '*** Match', -- 3
    'match body', -- 4
    '** Parent B', -- 5
    'no match body', -- 6
    '*** Also no match', -- 7
  }

  describe('show_matching', function()
    it('returns the number of matching headlines', function()
      local buf, win = make_win(SAMPLE)
      local n = sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      assert.are.equal(1, n)
    end)

    it('keeps a matching headline and its own body visible', function()
      local buf, win = make_win(SAMPLE)
      sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      assert.are.equal(-1, foldclosed_in(win, 3))
      assert.are.equal(-1, foldclosed_in(win, 4)) -- "match body"
    end)

    it('keeps every ancestor headline of a match visible', function()
      local buf, win = make_win(SAMPLE)
      sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      assert.are.equal(-1, foldclosed_in(win, 1)) -- Grandparent
      assert.are.equal(-1, foldclosed_in(win, 2)) -- Parent A
    end)

    it('folds away a non-matching sibling subtree', function()
      local buf, win = make_win(SAMPLE)
      sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      -- Parent B's subtree (lines 5-7) doesn't match and has no
      -- matching descendants, so it should be folded closed
      assert.are.equal(5, foldclosed_in(win, 5))
      assert.are.equal(5, foldclosed_in(win, 6))
      assert.are.equal(5, foldclosed_in(win, 7))
    end)

    it('matches multiple headlines independently', function()
      local buf, win = make_win(SAMPLE)
      local n = sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3 or lnum == 7
      end)
      assert.are.equal(2, n)
      assert.are.equal(-1, foldclosed_in(win, 7))
      assert.are.equal(-1, foldclosed_in(win, 5)) -- ancestor of the 2nd match
    end)

    it('returns 0 and folds everything when nothing matches', function()
      local buf, win = make_win(SAMPLE)
      local n = sparse.show_matching(buf, win, function()
        return false
      end)
      assert.are.equal(0, n)
      assert.are.equal(1, foldclosed_in(win, 1))
    end)
  end)

  describe('clear', function()
    it('restores the previous foldmethod', function()
      local buf, win = make_win(SAMPLE)
      vim.wo[win].foldmethod = 'marker'
      sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      assert.are.equal('manual', vim.wo[win].foldmethod)
      local ok = sparse.clear(win)
      assert.is_true(ok)
      assert.are.equal('marker', vim.wo[win].foldmethod)
    end)

    it('reopens folded lines', function()
      local buf, win = make_win(SAMPLE)
      sparse.show_matching(buf, win, function(_, lnum)
        return lnum == 3
      end)
      sparse.clear(win)
      assert.are.equal(-1, foldclosed_in(win, 5))
    end)

    it('returns nil for a window show_matching never touched', function()
      local _, win = make_win(SAMPLE)
      assert.is_nil(sparse.clear(win))
    end)
  end)

  describe('tag_search_interactive', function()
    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
    end)

    it('prompts for a tag match expression and applies it via mep.org.tagmatch/tags', function()
      local buf, win = make_win({ '* Task :work:', '* Other :home:' })
      vim.ui.input = function(_, on_confirm)
        on_confirm('+work')
      end
      sparse.tag_search_interactive(buf, win, {})
      assert.are.equal(-1, foldclosed_in(win, 1))
    end)

    it('does nothing on an invalid expression', function()
      local buf, win = make_win({ '* Task :work:' })
      vim.ui.input = function(_, on_confirm)
        on_confirm('not valid')
      end
      sparse.tag_search_interactive(buf, win, {})
      assert.is_false(sparse.clear(win) or false)
    end)

    it('does nothing when cancelled', function()
      local buf, win = make_win({ '* Task :work:' })
      vim.ui.input = function(_, on_confirm)
        on_confirm(nil)
      end
      sparse.tag_search_interactive(buf, win, {})
      assert.is_false(sparse.clear(win) or false)
    end)
  end)

  describe('todo_search_interactive', function()
    local orig_start
    before_each(function()
      orig_start = require('mep.picker').start
    end)
    after_each(function()
      require('mep.picker').start = orig_start
    end)

    it('opens a picker over the configured todo_keywords and applies the chosen one', function()
      local buf, win = make_win({ '* TODO Task', '* DONE Other' })
      local captured_items
      require('mep.picker').start = function(opts)
        captured_items = opts.items
        opts.on_select('TODO')
      end
      sparse.todo_search_interactive(buf, win, { 'TODO', 'DONE' })
      assert.are.same({ 'TODO', 'DONE' }, captured_items)
      assert.are.equal(-1, foldclosed_in(win, 1))
    end)

    it('warns and does not open a picker with no todo_keywords', function()
      local buf, win = make_win({ '* Task' })
      local called = false
      require('mep.picker').start = function()
        called = true
      end
      sparse.todo_search_interactive(buf, win, {})
      assert.is_false(called)
    end)
  end)
end)

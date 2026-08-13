local narrow = require('mep.org.narrow')

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

-- foldclosed()/foldlevel() are implicitly scoped to the *current* window
-- (there's no window argument), so checking them against a non-current
-- `win` (opened here with enter=false) silently reads the wrong window's
-- fold state -- must switch into it first.
local function foldclosed_in(win, lnum)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.foldclosed(lnum)
  end)
end

describe('mep.org.narrow', function()
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  -- Fold ranges of exactly 1 line never report as "closed" via
  -- foldclosed() in real Neovim (nothing beyond the summary line to
  -- hide) — use before/after regions of >1 line here so foldclosed()
  -- assertions are meaningful; is_narrowed()/foldlevel() cover the
  -- narrower 1-line case elsewhere.
  local SAMPLE = {
    '* One', 'body one a', 'body one b',
    '* Two',
    '* Three', 'body three',
  }

  describe('narrow', function()
    it('folds everything before and after the target subtree', function()
      local buf, win = make_win(SAMPLE)
      local result = narrow.narrow(buf, win, 4)
      assert.is_true(result)
      assert.are.equal(1, foldclosed_in(win, 1))
      assert.are.equal(5, foldclosed_in(win, 5))
      assert.are.equal(-1, foldclosed_in(win, 4))
    end)

    it('marks the window as narrowed', function()
      local buf, win = make_win(SAMPLE)
      narrow.narrow(buf, win, 4)
      assert.is_true(narrow.is_narrowed(win))
    end)

    it('does not fold a before-region when the target is the first headline', function()
      local buf, win = make_win(SAMPLE)
      narrow.narrow(buf, win, 1)
      assert.are.equal(-1, foldclosed_in(win, 1))
      assert.are.equal(4, foldclosed_in(win, 4))
    end)

    it('does not fold an after-region when the target is the last headline', function()
      local buf, win = make_win(SAMPLE)
      narrow.narrow(buf, win, 5)
      assert.are.equal(1, foldclosed_in(win, 1))
      assert.are.equal(-1, foldclosed_in(win, 5))
    end)

    it('returns nil and does nothing when lnum is not inside a headline', function()
      local buf, win = make_win({ 'no headline' })
      assert.is_nil(narrow.narrow(buf, win, 1))
      assert.is_false(narrow.is_narrowed(win))
    end)

    it('refuses to narrow a window that is already narrowed', function()
      local buf, win = make_win(SAMPLE)
      narrow.narrow(buf, win, 4)
      assert.is_nil(narrow.narrow(buf, win, 1))
    end)
  end)

  describe('widen', function()
    it('clears folds and the narrowed flag', function()
      local buf, win = make_win(SAMPLE)
      narrow.narrow(buf, win, 4)
      local result = narrow.widen(win)
      assert.is_true(result)
      assert.is_false(narrow.is_narrowed(win))
      assert.are.equal(-1, foldclosed_in(win, 1))
      assert.are.equal(-1, foldclosed_in(win, 5))
    end)

    it('restores the previous foldmethod', function()
      local buf, win = make_win(SAMPLE)
      vim.wo[win].foldmethod = 'marker'
      narrow.narrow(buf, win, 4)
      assert.are.equal('manual', vim.wo[win].foldmethod)
      narrow.widen(win)
      assert.are.equal('marker', vim.wo[win].foldmethod)
    end)

    it('returns nil for a window that was not narrowed', function()
      local buf, win = make_win(SAMPLE)
      assert.is_nil(narrow.widen(win))
    end)
  end)
end)

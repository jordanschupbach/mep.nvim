local visibility = require('mep.org.visibility')

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

-- foldclosed() is implicitly scoped to the *current* window (no window
-- argument exists), so checking it against a non-current `win` (opened
-- here with enter=false) silently reads the wrong window's fold state.
local function foldclosed_in(win, lnum)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.foldclosed(lnum)
  end)
end

describe('mep.org.visibility', function()
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  local SAMPLE = {
    '* Head one', -- 1
    'body one a', -- 2
    'body one b', -- 3
    '* Head two', -- 4
    'body two', -- 5
  }

  describe('cycle', function()
    it('goes overview -> contents -> all -> overview', function()
      local buf, win = make_win(SAMPLE)
      assert.are.equal('overview', visibility.cycle(buf, win))
      assert.are.equal('contents', visibility.cycle(buf, win))
      assert.are.equal('all', visibility.cycle(buf, win))
      assert.are.equal('overview', visibility.cycle(buf, win))
    end)

    it('overview uses the org foldexpr and closes everything (zM)', function()
      local buf, win = make_win(SAMPLE)
      visibility.cycle(buf, win) -- -> overview
      assert.are.equal('expr', vim.wo[win].foldmethod)
      assert.matches('mep%.org%.fold', vim.wo[win].foldexpr)
    end)

    it('contents hides body text but keeps every headline visible', function()
      local buf, win = make_win(SAMPLE)
      visibility.cycle(buf, win) -- overview
      visibility.cycle(buf, win) -- contents
      -- foldclosed(lnum) returns the *start line* of the closed fold lnum
      -- belongs to (whether lnum is the fold's own summary line or one of
      -- its hidden body lines), or -1 if lnum isn't in any closed fold —
      -- so every line here should resolve back to its headline's start.
      assert.are.equal(1, foldclosed_in(win, 1))
      assert.are.equal(1, foldclosed_in(win, 2)) -- body, inside the line-1 fold
      assert.are.equal(1, foldclosed_in(win, 3)) -- body, inside the line-1 fold
      assert.are.equal(4, foldclosed_in(win, 4))
      assert.are.equal(4, foldclosed_in(win, 5)) -- body, inside the line-4 fold
    end)

    it('all uses the org foldexpr and opens everything (zR)', function()
      local buf, win = make_win(SAMPLE)
      visibility.cycle(buf, win) -- overview
      visibility.cycle(buf, win) -- contents
      visibility.cycle(buf, win) -- all
      assert.are.equal('expr', vim.wo[win].foldmethod)
      for _, lnum in ipairs({ 1, 2, 3, 4, 5 }) do
        assert.are.equal(-1, foldclosed_in(win, lnum))
      end
    end)

    it('tracks state independently per window', function()
      local buf1, win1 = make_win(SAMPLE)
      local buf2, win2 = make_win(SAMPLE)
      visibility.cycle(buf1, win1) -- win1 -> overview
      visibility.cycle(buf2, win2) -- win2 -> overview
      visibility.cycle(buf2, win2) -- win2 -> contents
      assert.are.equal('overview', visibility.state(win1))
      assert.are.equal('contents', visibility.state(win2))
    end)
  end)

  describe('state', function()
    it('returns nil before cycle has ever been called for a window', function()
      local _, win = make_win(SAMPLE)
      assert.is_nil(visibility.state(win))
    end)
  end)
end)

local snippet = require('mep.snippet')
local registry = require('mep.snippet.registry')
local session = require('mep.snippet.session')
local config = require('mep.snippet.config')

local function make_buf_win(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if filetype then
    vim.bo[buf].filetype = filetype
  end
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 40, height = 5 })
  return buf, win
end

local function set_cursor_after(win, lnum, col)
  vim.cmd('startinsert')
  vim.api.nvim_win_set_cursor(win, { lnum, col })
  vim.cmd('stopinsert')
end

local function keymap_callback(mode, lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == lhs then
      return m.callback
    end
  end
  return nil
end

describe('mep.snippet', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
    registry._reset()
    session._reset()
    pcall(vim.keymap.del, 'i', '<Tab>')
    pcall(vim.keymap.del, 'i', '<S-Tab>')
    -- A couple of tests below keep Insert mode active (via startinsert)
    -- across an assertion so an end-of-line tabstop's column isn't
    -- clamped away by Normal-mode cursor rules; a failed assertion would
    -- otherwise skip that test's own stopinsert and leak Insert mode
    -- into every later spec file sharing this busted run.
    pcall(vim.cmd, 'stopinsert')
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  describe('add', function()
    it('registers a snippet, findable via the registry', function()
      snippet.add('lua', { { trigger = 'fn', body = 'function $1()\n\t$0\nend' } })
      assert.is_not_nil(registry.find('lua', 'fn'))
    end)
  end)

  describe('expand_at_cursor', function()
    it('expands the registered trigger before the cursor', function()
      snippet.add('lua', { { trigger = 'fn', body = 'F$1' } })
      local buf, win = make_buf_win({ 'fn' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)

      assert.is_true(snippet.expand_at_cursor(buf, win))
      assert.are.same({ 'F' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('returns false when there is no word before the cursor', function()
      local buf, win = make_buf_win({ '' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 0)
      assert.is_false(snippet.expand_at_cursor(buf, win))
    end)

    it('returns false for an unregistered trigger', function()
      local buf, win = make_buf_win({ 'nope' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 4)
      assert.is_false(snippet.expand_at_cursor(buf, win))
    end)

    it('is scoped to the buffer\'s own filetype', function()
      snippet.add('python', { { trigger = 'fn', body = 'F$1' } })
      local buf, win = make_buf_win({ 'fn' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      assert.is_false(snippet.expand_at_cursor(buf, win))
    end)
  end)

  describe('expand', function()
    it('expands the given body directly, bypassing trigger lookup', function()
      local buf, win = make_buf_win({ 'xx' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)
      snippet.expand(buf, win, 2, 'F$1')
      assert.are.same({ 'F' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)

  describe('setup', function()
    it('binds <Tab>/<S-Tab> in insert mode by default', function()
      snippet.setup({})
      assert.is_not_nil(keymap_callback('i', '<Tab>'))
      assert.is_not_nil(keymap_callback('i', '<S-Tab>'))
    end)

    it('does not bind the keymaps when tab_keymap = false', function()
      snippet.setup({ tab_keymap = false })
      assert.is_nil(keymap_callback('i', '<Tab>'))
      assert.is_nil(keymap_callback('i', '<S-Tab>'))
    end)

    it('returns the resolved options', function()
      local options = snippet.setup({ tab_keymap = false })
      assert.is_false(options.tab_keymap)
    end)
  end)

  describe('<Tab> behavior', function()
    it('jumps to the next tabstop when a session is active', function()
      snippet.setup({})
      local buf, win = make_buf_win({ 'x' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 1)
      -- $2 lands one-past-the-last-character — Insert mode has to stay
      -- active across the jump (as it genuinely would for a real <Tab>
      -- press) or Normal-mode cursor clamping moves it back a column;
      -- see mep.snippet.session_spec.lua's own note on this.
      vim.cmd('startinsert')
      session.expand(buf, win, 1, '$1-$2')
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))

      keymap_callback('i', '<Tab>')()
      assert.are.same({ 1, 1 }, vim.api.nvim_win_get_cursor(win))
      vim.cmd('stopinsert')
    end)

    it('expands a matching trigger when no session is active', function()
      snippet.setup({})
      snippet.add('lua', { { trigger = 'fn', body = 'F$1' } })
      local buf, win = make_buf_win({ 'fn' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 2)

      keymap_callback('i', '<Tab>')()
      assert.are.same({ 'F' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('feeds a literal <Tab> when nothing matches and no session is active', function()
      snippet.setup({})
      local _, win = make_buf_win({ '' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 0)

      -- Mocked rather than left to really queue into Neovim's typeahead
      -- buffer: nvim_feedkeys(..., 'n', ...) only *queues* keys (unlike
      -- 'x', it doesn't execute them immediately), so a real call here
      -- would sit unconsumed in the shared busted session's typeahead
      -- and get processed later by some *other* spec file's own
      -- feedkeys(..., 'x', ...) call — confirmed the hard way: this
      -- exact gap was leaking a stray <Tab> into spec/mep/symbols/
      -- symbols_spec.lua, throwing off its own <CR> keypress test.
      local orig_feedkeys = vim.api.nvim_feedkeys
      local fed
      vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
        fed = { keys = keys, mode = mode, escape_ks = escape_ks }
      end
      keymap_callback('i', '<Tab>')()
      vim.api.nvim_feedkeys = orig_feedkeys

      assert.is_not_nil(fed)
      assert.are.equal(vim.api.nvim_replace_termcodes('<Tab>', true, false, true), fed.keys)
      assert.are.equal('n', fed.mode)
    end)
  end)

  describe('<S-Tab> behavior', function()
    it('jumps to the previous tabstop when a session is active', function()
      snippet.setup({})
      local buf, win = make_buf_win({ 'x' }, 'lua')
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 1)
      -- $2 lands one-past-the-last-character — see the <Tab> behavior
      -- test above for why Insert mode has to stay active across the
      -- jump for that column to land exactly.
      vim.cmd('startinsert')
      session.expand(buf, win, 1, '$1-$2')
      keymap_callback('i', '<Tab>')() -- to $2
      assert.are.same({ 1, 1 }, vim.api.nvim_win_get_cursor(win))

      keymap_callback('i', '<S-Tab>')() -- back to $1
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
      vim.cmd('stopinsert')
    end)

    it('feeds a literal <S-Tab> when no session is active', function()
      snippet.setup({})
      -- Mocked for the same reason the equivalent <Tab> test above
      -- mocks it — see that test's own comment.
      local orig_feedkeys = vim.api.nvim_feedkeys
      local fed
      vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
        fed = { keys = keys, mode = mode, escape_ks = escape_ks }
      end
      keymap_callback('i', '<S-Tab>')()
      vim.api.nvim_feedkeys = orig_feedkeys

      assert.is_not_nil(fed)
      assert.are.equal(vim.api.nvim_replace_termcodes('<S-Tab>', true, false, true), fed.keys)
    end)
  end)
end)

local hints = require('mep.hints')
local config = require('mep.hints.config')
local ui = require('mep.hints.ui')

local ns = vim.api.nvim_create_namespace('mep_hints')

--- Stubs mep.hints.read_key to return each of `keys` in order (one per
--- call), restoring the original in the returned function.
local function stub_keys(keys)
  local original = hints.read_key
  local i = 0
  hints.read_key = function()
    i = i + 1
    return keys[i]
  end
  return function()
    hints.read_key = original
  end
end

describe('mep.hints', function()
  local bufnr, win
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    bufnr = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(bufnr, true, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 40,
      height = 10,
    })
  end)

  after_each(function()
    config.options = saved_options
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    ui.clear(bufnr)
  end)

  describe('select', function()
    it('notifies and does nothing for zero targets', function()
      local notified
      local original_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      hints.select(win, bufnr, {})
      vim.notify = original_notify
      assert.is_not_nil(notified)
      assert.matches('no matches', notified)
    end)

    it('jumps immediately for a single target, without reading a key', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello world' })
      local restore = stub_keys({})
      hints.select(win, bufnr, { { lnum = 1, col = 6, len = 5 } })
      restore()
      assert.are.same({ 1, 6 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('jumps to the target whose single-character label was pressed', function()
      config.setup({ labels = 'abcdefghijklmnopqrstuvwxyz' })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo bar baz' })
      local restore = stub_keys({ 'b' }) -- 2nd target's label ('a', 'b', 'c' in charset order)
      hints.select(win, bufnr, {
        { lnum = 1, col = 0, len = 3 },
        { lnum = 1, col = 4, len = 3 },
        { lnum = 1, col = 8, len = 3 },
      })
      restore()
      assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('clears the overlay and does not move the cursor on <Esc>', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo bar baz' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local restore = stub_keys({ '\27' })
      hints.select(win, bufnr, {
        { lnum = 1, col = 0, len = 3 },
        { lnum = 1, col = 4, len = 3 },
      })
      restore()
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
    end)

    it('cancels cleanly when the pressed key matches no label', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo bar' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local restore = stub_keys({ 'z' })
      hints.select(win, bufnr, {
        { lnum = 1, col = 0, len = 3 },
        { lnum = 1, col = 4, len = 3 },
      })
      restore()
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('resolves two-character labels once targets exceed the charset', function()
      config.setup({ labels = 'ab' })
      local words = {}
      for i = 1, 4 do
        words[i] = 'w' .. i
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { table.concat(words, ' ') })
      local targets = require('mep.hints.targets').word_starts(bufnr, 1, 1)
      assert.are.equal(4, #targets) -- forces 2-char labels: aa, ab, ba, bb

      -- Third target's label is 'ba' (i=2 -> 'b', j=1 -> 'a').
      local restore = stub_keys({ 'b', 'a' })
      hints.select(win, bufnr, targets)
      restore()
      assert.are.same({ 1, targets[3].col }, vim.api.nvim_win_get_cursor(win))
    end)

    it('cancels a two-character selection on <Esc> as the second key', function()
      config.setup({ labels = 'ab' })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'w1 w2 w3 w4' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local targets = require('mep.hints.targets').word_starts(bufnr, 1, 1)
      local restore = stub_keys({ 'a', '\27' })
      hints.select(win, bufnr, targets)
      restore()
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end)
  end)

  describe('char_search', function()
    it('prompts for a character, then jumps to the labeled occurrence chosen', function()
      -- 'x' occurs at cols 0, 2, 5; labels are assigned in that order
      -- ('a', 'b', 'c'), so pressing 'b' selects the occurrence at col 2.
      config.setup({ labels = 'abcdefghijklmnopqrstuvwxyz' })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'xax bxb' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local restore = stub_keys({ 'x', 'b' })
      hints.char_search()
      restore()
      assert.are.same({ 1, 2 }, vim.api.nvim_win_get_cursor(win))
    end)

    it('cancels before labeling anything on <Esc> at the prompt', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'xax' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local restore = stub_keys({ '\27' })
      hints.char_search()
      restore()
      assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
    end)
  end)

  describe('word_start', function()
    it('labels visible word starts and jumps to the one selected', function()
      config.setup({ labels = 'abcdefghijklmnopqrstuvwxyz' })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha beta gamma' })
      local restore = stub_keys({ 'b' })
      hints.word_start()
      restore()
      assert.are.same({ 1, 6 }, vim.api.nvim_win_get_cursor(win))
    end)
  end)

  describe('setup', function()
    it('binds triggers.char/word as normal-mode keymaps', function()
      config.setup({ triggers = { char = { '<localleader>hc' }, word = { '<localleader>hw' } } })
      hints.setup(config.options)
      local char_map = vim.fn.maparg('<localleader>hc', 'n', false, true)
      local word_map = vim.fn.maparg('<localleader>hw', 'n', false, true)
      assert.is_not_nil(next(char_map))
      assert.is_not_nil(next(word_map))
      vim.keymap.del('n', '<localleader>hc')
      vim.keymap.del('n', '<localleader>hw')
    end)

    it('leaves triggers unbound by default', function()
      local options = hints.setup({})
      assert.are.same({}, options.triggers.char)
      assert.are.same({}, options.triggers.word)
    end)
  end)
end)

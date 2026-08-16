local engine = require('mep.completion.engine')
local completion_mod = require('mep.completion.completion')
local config = require('mep.completion.config')

local function make_buf_win(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 30, height = 5 })
  return buf, win
end

-- Normal-mode nvim_win_set_cursor clamps to the last real character
-- (one short of "one past the end"), so a cursor genuinely sitting right
-- after the last typed character — the position completion actually
-- cares about — needs to be set while briefly in Insert mode, the same
-- technique mep.org.templates_spec.lua's own `set_cursor_after` uses.
local function set_cursor_after(win, lnum, col)
  vim.cmd('startinsert')
  vim.api.nvim_win_set_cursor(win, { lnum, col })
  vim.cmd('stopinsert')
end

describe('mep.completion.engine', function()
  local orig_mode, orig_complete
  local saved_config

  before_each(function()
    orig_mode = engine._mode
    orig_complete = vim.fn.complete
    saved_config = vim.deepcopy(config.options)
    engine._mode = function()
      return 'i'
    end
  end)

  after_each(function()
    engine._mode = orig_mode
    vim.fn.complete = orig_complete
    config.options = saved_config
    completion_mod.sources.__test_a = nil
    completion_mod.sources.__test_b = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  describe('_context', function()
    it('extracts the keyword prefix and a 1-based startcol', function()
      local buf, win = make_buf_win({ 'local foo' })
      set_cursor_after(win, 1, 9) -- right after "foo"
      local ctx = engine._context(buf, win)
      assert.are.equal('foo', ctx.prefix)
      assert.are.equal(7, ctx.startcol) -- col('.') would be 10; 10 - 3 = 7
    end)

    it('is an empty prefix right after a non-keyword character', function()
      local buf, win = make_buf_win({ 'local x = ' })
      set_cursor_after(win, 1, 10)
      local ctx = engine._context(buf, win)
      assert.are.equal('', ctx.prefix)
    end)
  end)

  describe('_dedupe', function()
    it('keeps the first occurrence of a duplicate word', function()
      local items = {
        { word = 'foo', menu = '[A]' },
        { word = 'bar', menu = '[A]' },
        { word = 'foo', menu = '[B]' },
      }
      local result = engine._dedupe(items)
      assert.are.equal(2, #result)
      assert.are.equal('[A]', result[1].menu)
    end)
  end)

  describe('trigger', function()
    it('does nothing when not in insert mode', function()
      engine._mode = function()
        return 'n'
      end
      local called = false
      vim.fn.complete = function()
        called = true
      end
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, config.options)
      assert.is_false(called)
    end)

    it('does nothing when the prefix is shorter than min_chars', function()
      local called = false
      vim.fn.complete = function()
        called = true
      end
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'foobar' } })
      end }
      local buf, win = make_buf_win({ 'f' })
      set_cursor_after(win, 1, 1)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 2, max_items = 50 })
      assert.is_false(called)
    end)

    it('override_min_chars bypasses the configured min_chars', function()
      local captured
      vim.fn.complete = function(startcol, items)
        captured = { startcol, items }
      end
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'foobar' } })
      end }
      local buf, win = make_buf_win({ '' })
      set_cursor_after(win, 1, 0)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 5, max_items = 50 }, 0)
      assert.is_not_nil(captured)
    end)

    it('merges results from multiple sources into one complete() call', function()
      local captured
      vim.fn.complete = function(startcol, items)
        captured = { startcol, items }
      end
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'fooA' } })
      end }
      completion_mod.sources.__test_b = { complete = function(_, cb)
        cb({ { word = 'fooB' } })
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { '__test_a', '__test_b' }, min_chars = 1, max_items = 50 })

      local words = {}
      for _, it in ipairs(captured[2]) do
        words[#words + 1] = it.word
      end
      table.sort(words)
      assert.are.same({ 'fooA', 'fooB' }, words)
    end)

    it('waits for a slower (asynchronously-resolved) source before calling complete()', function()
      local captured
      vim.fn.complete = function(_, items)
        captured = items
      end
      local pending_cb
      completion_mod.sources.__test_a = { complete = function(_, cb)
        pending_cb = cb -- deliberately not called yet
      end }
      completion_mod.sources.__test_b = { complete = function(_, cb)
        cb({ { word = 'fast' } })
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { '__test_a', '__test_b' }, min_chars = 1, max_items = 50 })

      assert.is_nil(captured) -- __test_a hasn't answered yet
      pending_cb({ { word = 'slow' } })
      assert.is_not_nil(captured)
      assert.are.equal(2, #captured)
    end)

    it('skips an unregistered source name without hanging', function()
      local captured
      vim.fn.complete = function(_, items)
        captured = items
      end
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'foobar' } })
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { 'nope', '__test_a' }, min_chars = 1, max_items = 50 })
      assert.are.equal(1, #captured)
    end)

    it('trims to max_items after merging', function()
      local captured
      vim.fn.complete = function(_, items)
        captured = items
      end
      completion_mod.sources.__test_a = {
        complete = function(_, cb)
          cb({ { word = 'a1' }, { word = 'a2' }, { word = 'a3' } })
        end,
      }
      local buf, win = make_buf_win({ 'a' })
      set_cursor_after(win, 1, 1)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 2 })
      assert.are.equal(2, #captured)
    end)

    it('discards a stale response from a superseded trigger() call', function()
      local complete_calls = 0
      vim.fn.complete = function()
        complete_calls = complete_calls + 1
      end
      local pending_cb
      completion_mod.sources.__test_a = { complete = function(_, cb)
        pending_cb = cb
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)

      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 50 })
      local first_cb = pending_cb
      -- a second trigger supersedes the first before it resolves
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 50 })
      first_cb({ { word = 'stale' } })
      assert.are.equal(0, complete_calls)
      pending_cb({ { word = 'fresh' } })
      assert.are.equal(1, complete_calls)
    end)

    it('discards a response that arrives after leaving insert mode', function()
      local called = false
      vim.fn.complete = function()
        called = true
      end
      local pending_cb
      completion_mod.sources.__test_a = { complete = function(_, cb)
        pending_cb = cb
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 50 })

      engine._mode = function()
        return 'n'
      end
      pending_cb({ { word = 'toolate' } })
      assert.is_false(called)
    end)

    it('discards a response after the cursor has moved to a different line', function()
      local called = false
      vim.fn.complete = function()
        called = true
      end
      local pending_cb
      completion_mod.sources.__test_a = { complete = function(_, cb)
        pending_cb = cb
      end }
      local buf, win = make_buf_win({ 'foo', 'bar' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 50 })

      set_cursor_after(win, 2, 3)
      pending_cb({ { word = 'toolate' } })
      assert.is_false(called)
    end)

    it('does not call complete() when nothing matched', function()
      local called = false
      vim.fn.complete = function()
        called = true
      end
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({})
      end }
      local buf, win = make_buf_win({ 'foo' })
      set_cursor_after(win, 1, 3)
      engine.trigger(buf, win, { sources = { '__test_a' }, min_chars = 1, max_items = 50 })
      assert.is_false(called)
    end)
  end)

  describe('encode_snippet_user_data / _decode_snippet_user_data', function()
    it('round-trips a snippet body', function()
      local encoded = engine.encode_snippet_user_data('function $1($2)\n\t$0\nend')
      assert.are.equal('function $1($2)\n\t$0\nend', engine._decode_snippet_user_data(encoded))
    end)

    it('returns nil for an empty/nil/unrelated user_data string', function()
      assert.is_nil(engine._decode_snippet_user_data(nil))
      assert.is_nil(engine._decode_snippet_user_data(''))
      assert.is_nil(engine._decode_snippet_user_data('plain string'))
      assert.is_nil(engine._decode_snippet_user_data('{"other":true}'))
    end)
  end)

  describe('CompleteDone handling', function()
    local orig_snippet, orig_completed_item

    before_each(function()
      orig_snippet = package.loaded['mep.snippet']
      orig_completed_item = vim.v.completed_item
    end)

    after_each(function()
      package.loaded['mep.snippet'] = orig_snippet
      vim.v.completed_item = orig_completed_item
      engine.disable()
    end)

    it('expands the real snippet body once a snippet-shaped item is accepted', function()
      local expand_call
      package.loaded['mep.snippet'] = {
        expand = function(bufnr, win, replace_len, body)
          expand_call = { bufnr = bufnr, win = win, replace_len = replace_len, body = body }
        end,
      }
      engine.enable()
      local buf, win = make_buf_win({ 'fn' })
      vim.api.nvim_set_current_win(win)
      vim.v.completed_item = { word = 'fn', user_data = engine.encode_snippet_user_data('function $1($2)\n\t$0\nend') }
      vim.api.nvim_exec_autocmds('CompleteDone', { buffer = buf })

      assert.is_not_nil(expand_call)
      assert.are.equal(2, expand_call.replace_len) -- #"fn"
      assert.are.equal('function $1($2)\n\t$0\nend', expand_call.body)
    end)

    it('does nothing for a plain (non-snippet) accepted item', function()
      local called = false
      package.loaded['mep.snippet'] = {
        expand = function()
          called = true
        end,
      }
      engine.enable()
      local buf = make_buf_win({ 'foo' })
      vim.v.completed_item = { word = 'foo', user_data = '' }
      vim.api.nvim_exec_autocmds('CompleteDone', { buffer = buf })
      assert.is_false(called)
    end)
  end)

  describe('enable / disable', function()
    after_each(function()
      engine.disable()
    end)

    it('debounce-triggers on TextChangedI in the current buffer', function()
      config.setup({ sources = { '__test_a' }, min_chars = 1, debounce_ms = 5 })
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'foobar' } })
      end }
      local captured
      vim.fn.complete = function(_, items)
        captured = items
      end

      engine.enable()
      local buf, win = make_buf_win({ 'foo' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 3)
      vim.api.nvim_exec_autocmds('TextChangedI', { buffer = buf })

      vim.wait(500, function()
        return captured ~= nil
      end, 10)
      assert.is_not_nil(captured)
    end)

    it('does not debounce-trigger on TextChangedI when auto_trigger is false', function()
      config.setup({ sources = { '__test_a' }, min_chars = 1, debounce_ms = 5, auto_trigger = false })
      completion_mod.sources.__test_a = { complete = function(_, cb)
        cb({ { word = 'foobar' } })
      end }
      local called = false
      vim.fn.complete = function()
        called = true
      end

      engine.enable()
      local buf, win = make_buf_win({ 'foo' })
      vim.api.nvim_set_current_win(win)
      set_cursor_after(win, 1, 3)
      vim.api.nvim_exec_autocmds('TextChangedI', { buffer = buf })

      vim.wait(100, function()
        return called
      end, 10)
      assert.is_false(called)
    end)

    it('applies configured completeopt and restores the previous value on disable', function()
      local orig = vim.o.completeopt
      vim.o.completeopt = 'menu,preview'
      config.setup({ completeopt = { 'menu', 'menuone', 'noselect' } })

      engine.enable()
      assert.are.equal('menu,menuone,noselect', vim.o.completeopt)

      engine.disable()
      assert.are.equal('menu,preview', vim.o.completeopt)
      vim.o.completeopt = orig
    end)

    it('binds the manual trigger keymap in insert mode', function()
      config.setup({ keymaps = { trigger = { '<F6>' } } })
      engine.enable()
      local maps = vim.api.nvim_get_keymap('i')
      local found = false
      for _, m in ipairs(maps) do
        if m.lhs == '<F6>' then
          found = true
        end
      end
      assert.is_true(found)
      pcall(vim.keymap.del, 'i', '<F6>')
    end)

    it('disable removes the augroup and the trigger keymap', function()
      config.setup({ keymaps = { trigger = { '<F7>' } } })
      engine.enable()
      engine.disable()
      local maps = vim.api.nvim_get_keymap('i')
      for _, m in ipairs(maps) do
        assert.are_not.equal('<F7>', m.lhs)
      end
    end)
  end)
end)

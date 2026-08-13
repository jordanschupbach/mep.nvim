local Picker = require('mep.picker.engine')
local picker_config = require('mep.picker.config')

local function set_prompt_text(p, text)
  vim.api.nvim_buf_set_lines(p.layout.prompt_buf, 0, 1, false, { text })
end

describe('mep.picker.engine', function()
  local p

  after_each(function()
    if p and not p.closed then
      pcall(function()
        p:close()
      end)
    end
    p = nil
  end)

  describe('Picker.new validation', function()
    it('requires entry_to_string', function()
      assert.has_error(function()
        Picker.new({ items = {} })
      end)
    end)

    it('requires items or get_items', function()
      assert.has_error(function()
        Picker.new({ entry_to_string = function() end })
      end)
    end)

    it('accepts get_items without items', function()
      assert.has_no.errors(function()
        Picker.new({ entry_to_string = function() end, get_items = function() end })
      end)
    end)
  end)

  describe('static item source', function()
    local items

    before_each(function()
      items = { { name = 'apple' }, { name = 'banana' }, { name = 'grape' } }
      p = Picker.new({
        items = items,
        entry_to_string = function(i)
          return i.name
        end,
      })
    end)

    it('shows every item for an empty query on open', function()
      p:open()
      assert.are.equal(3, #p.results)
    end)

    it('filters results as the query changes', function()
      p:open()
      set_prompt_text(p, 'gr')
      p:on_text_changed()
      assert.are.equal(1, #p.results)
      assert.are.equal('grape', p:current_item().name)
    end)

    it('does not re-filter when the prompt text has not actually changed', function()
      p:open()
      set_prompt_text(p, 'gr')
      p:on_text_changed() -- settles self.query to 'gr'

      local filter_calls = 0
      local orig = p.apply_filter
      p.apply_filter = function(self, ...)
        filter_calls = filter_calls + 1
        return orig(self, ...)
      end
      p:on_text_changed() -- text is still 'gr': nothing actually changed
      assert.are.equal(0, filter_calls)
    end)

    it('move() steps through results and wraps around in both directions', function()
      p:open()
      assert.are.equal(1, p.selected)
      p:move(1)
      assert.are.equal(2, p.selected)
      p:move(1)
      assert.are.equal(3, p.selected)
      p:move(1)
      assert.are.equal(1, p.selected) -- wraps forward past the end
      p:move(-1)
      assert.are.equal(3, p.selected) -- wraps backward past the start
    end)

    it('move() keeps the selected-row highlight in sync (not just p.selected)', function()
      p:open()
      p:move(1)
      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      local marks = vim.api.nvim_buf_get_extmarks(p.layout.results_buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2]) -- row 2 (1-based) -> 0-based extmark row 1
    end)

    it('select() calls on_select with the current item and closes the picker', function()
      local selected
      p.opts.on_select = function(item)
        selected = item
      end
      p:open()
      p:move(1) -- banana
      p:select()

      assert.are.equal('banana', selected.name)
      assert.is_true(p.closed)
      assert.is_nil(p.layout)
    end)

    it('select() with no results just closes, without calling on_select', function()
      local called = false
      p.opts.on_select = function()
        called = true
      end
      p:open()
      set_prompt_text(p, 'nonexistent-query')
      p:on_text_changed()
      p:select()

      assert.is_false(called)
      assert.is_true(p.closed)
    end)

    it('refresh() re-applies the current query against a mutated items table', function()
      p:open()
      set_prompt_text(p, 'kiwi')
      p:on_text_changed()
      assert.are.equal(0, #p.results)

      table.insert(items, { name = 'kiwi' })
      p:refresh()

      assert.are.equal(1, #p.results)
      assert.are.equal('kiwi', p.results[1].item.name)
    end)

    it('close() is idempotent', function()
      p:open()
      p:close()
      assert.has_no.errors(function()
        p:close()
      end)
    end)

    it('calls opts.on_close when closing', function()
      local closed_called = false
      p.opts.on_close = function()
        closed_called = true
      end
      p:open()
      p:close()
      assert.is_true(closed_called)
    end)

    -- open() starts insert mode (so you can type a query immediately) via
    -- `vim.cmd.startinsert()`; close() must undo that with its own
    -- `vim.cmd.stopinsert()`, or insert mode (global editor state, not
    -- per-window) leaks into whichever window/buffer regains focus once
    -- the prompt window is gone.
    it('close() stops insert mode before tearing down the layout', function()
      local orig_stopinsert = vim.cmd.stopinsert
      local call_order = {}
      vim.cmd.stopinsert = function()
        call_order[#call_order + 1] = 'stopinsert'
      end
      local orig_close_win = vim.api.nvim_win_close
      vim.api.nvim_win_close = function(...)
        call_order[#call_order + 1] = 'win_close'
        return orig_close_win(...)
      end

      p:open()
      p:close()

      vim.cmd.stopinsert = orig_stopinsert
      vim.api.nvim_win_close = orig_close_win

      assert.are.equal('stopinsert', call_order[1])
      assert.are.equal('win_close', call_order[2])
    end)

    it('select() stops insert mode too (it closes via the same path)', function()
      local orig_stopinsert = vim.cmd.stopinsert
      local called = false
      vim.cmd.stopinsert = function()
        called = true
      end

      p:open()
      p:select()

      vim.cmd.stopinsert = orig_stopinsert
      assert.is_true(called)
    end)

    it('opening a new picker closes the previously active one', function()
      p:open()
      local first = p

      local second = Picker.new({
        items = { { name = 'x' } },
        entry_to_string = function(i)
          return i.name
        end,
      })
      second:open()

      assert.is_true(first.closed)
      assert.is_false(second.closed)

      second:close()
    end)
  end)

  describe('dynamic (get_items) source', function()
    it('calls get_items with the current query and renders its results', function()
      local seen_query
      p = Picker.new({
        entry_to_string = function(i)
          return i.display
        end,
        get_items = function(query, callback)
          seen_query = query
          callback({ { display = 'result-for-' .. query } })
        end,
      })
      p:open()
      set_prompt_text(p, 'needle')
      p:on_text_changed()

      assert.are.equal('needle', seen_query)
      assert.are.equal(1, #p.results)
      assert.are.equal('result-for-needle', p.results[1].item.display)
    end)

    it('ignores a stale callback from a superseded query', function()
      local pending_callback
      p = Picker.new({
        entry_to_string = function(i)
          return i.display
        end,
        get_items = function(query, callback)
          if query == 'first' then
            pending_callback = callback -- deliberately not called yet
          else
            callback({ { display = query } })
          end
        end,
      })
      p:open()

      set_prompt_text(p, 'first')
      p:on_text_changed()
      assert.is_not_nil(pending_callback)

      set_prompt_text(p, 'second')
      p:on_text_changed()
      assert.are.equal(1, #p.results)
      assert.are.equal('second', p.results[1].item.display)

      -- the stale 'first' query's callback finally fires; it must not
      -- clobber the already-current 'second' results
      pending_callback({ { display = 'first' } })
      assert.are.equal(1, #p.results)
      assert.are.equal('second', p.results[1].item.display)
    end)
  end)

  describe('preview integration', function()
    it('calls opts.preview with the current item on open and on move', function()
      local previewed = {}
      p = Picker.new({
        items = { { name = 'a' }, { name = 'b' } },
        entry_to_string = function(i)
          return i.name
        end,
        preview = function(item)
          table.insert(previewed, item.name)
        end,
      })
      p:open()
      p:move(1)

      assert.are.same({ 'a', 'b' }, previewed)
    end)

    it('clears the preview pane when filtering yields no results', function()
      local preview_mod = require('mep.picker.preview')
      local orig_clear = preview_mod.clear
      local clear_calls = 0
      preview_mod.clear = function(...)
        clear_calls = clear_calls + 1
        return orig_clear(...)
      end

      p = Picker.new({
        items = { { name = 'only' } },
        entry_to_string = function(i)
          return i.name
        end,
      })
      p:open()
      set_prompt_text(p, 'no-match-for-this')
      p:on_text_changed()

      preview_mod.clear = orig_clear
      assert.is_true(clear_calls > 0)
      assert.are.equal(0, #p.results)
    end)
  end)

  describe('opts.on_open', function()
    it('is called once the layout exists', function()
      local layout_was_ready = false
      p = Picker.new({
        items = {},
        entry_to_string = function(i)
          return i.name
        end,
        on_open = function(picker)
          layout_was_ready = picker.layout ~= nil
        end,
      })
      p:open()
      assert.is_true(layout_was_ready)
    end)
  end)

  describe('mep.picker.config integration', function()
    local saved_options

    before_each(function()
      saved_options = vim.deepcopy(picker_config.options)
    end)

    after_each(function()
      picker_config.options = saved_options
    end)

    local function new_static_picker()
      return Picker.new({
        items = { { name = 'apple' }, { name = 'kiwi' } },
        entry_to_string = function(i)
          return i.name
        end,
      })
    end

    it('maps the default keymaps as buffer-local mappings on open', function()
      p = new_static_picker()
      p:open()
      assert.are.equal(1, vim.fn.maparg('<CR>', 'i', false, true).buffer)
      assert.are.equal(1, vim.fn.maparg('<Esc>', 'i', false, true).buffer)
      assert.are.equal(1, vim.fn.maparg('<C-n>', 'i', false, true).buffer)
    end)

    it('maps a configured keymap override instead of the default', function()
      picker_config.setup({ keymaps = { select = { '<C-y>' } } })
      p = new_static_picker()
      p:open()
      assert.are.equal(1, vim.fn.maparg('<C-y>', 'i', false, true).buffer)
    end)

    it('honors a configured static debounce_ms via the real autocmd path', function()
      picker_config.setup({ debounce_ms = { static = 5 } })
      p = new_static_picker()
      p:open()
      set_prompt_text(p, 'kiwi')
      vim.api.nvim_exec_autocmds('TextChangedI', { buffer = p.layout.prompt_buf })

      vim.wait(300, function()
        return #p.results == 1
      end, 5)

      assert.are.equal(1, #p.results)
      assert.are.equal('kiwi', p.results[1].item.name)
    end)
  end)
end)

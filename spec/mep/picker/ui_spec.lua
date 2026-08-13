local ui = require('mep.picker.ui')

describe('mep.picker.ui', function()
  describe('create_layout / close_layout', function()
    it('creates three valid floating windows with scratch buffers', function()
      local layout = ui.create_layout({ title = 'Test' })

      for _, win in ipairs({ layout.prompt_win, layout.results_win, layout.preview_win }) do
        assert.is_true(vim.api.nvim_win_is_valid(win))
      end
      for _, buf in ipairs({ layout.prompt_buf, layout.results_buf, layout.preview_buf }) do
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
        assert.are.equal('nofile', vim.bo[buf].buftype)
        assert.are.equal('wipe', vim.bo[buf].bufhidden)
      end

      ui.close_layout(layout)
    end)

    it('sets results and preview window options for a list/preview UI', function()
      local layout = ui.create_layout({ title = 'Test' })

      assert.is_true(vim.wo[layout.results_win].cursorline)
      assert.is_false(vim.wo[layout.results_win].wrap)
      assert.is_false(vim.wo[layout.preview_win].wrap)
      assert.is_true(vim.wo[layout.preview_win].number)
      assert.is_false(vim.bo[layout.preview_buf].modifiable)

      ui.close_layout(layout)
    end)

    it('close_layout invalidates all three windows', function()
      local layout = ui.create_layout({ title = 'Test' })
      ui.close_layout(layout)

      assert.is_false(vim.api.nvim_win_is_valid(layout.prompt_win))
      assert.is_false(vim.api.nvim_win_is_valid(layout.results_win))
      assert.is_false(vim.api.nvim_win_is_valid(layout.preview_win))
    end)

    it('close_layout is safe to call on an already-closed layout', function()
      local layout = ui.create_layout({ title = 'Test' })
      ui.close_layout(layout)
      assert.has_no.errors(function()
        ui.close_layout(layout)
      end)
    end)
  end)

  describe('render_results', function()
    local layout

    before_each(function()
      layout = ui.create_layout({ title = 'Test' })
    end)

    after_each(function()
      ui.close_layout(layout)
    end)

    local function entry_to_string(item)
      return item.name
    end

    it('writes one line per result, in order', function()
      local results = {
        { item = { name = 'alpha' } },
        { item = { name = 'beta' } },
      }
      ui.render_results(layout, results, entry_to_string, 1)

      local lines = vim.api.nvim_buf_get_lines(layout.results_buf, 0, -1, false)
      assert.are.same({ 'alpha', 'beta' }, lines)
    end)

    it('moves the results window cursor to the clamped selected index', function()
      local results = {
        { item = { name = 'a' } },
        { item = { name = 'b' } },
        { item = { name = 'c' } },
      }
      ui.render_results(layout, results, entry_to_string, 2)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(layout.results_win)[1])

      -- an out-of-range index is clamped to the last result
      ui.render_results(layout, results, entry_to_string, 99)
      assert.are.equal(3, vim.api.nvim_win_get_cursor(layout.results_win)[1])
    end)

    it('handles an empty result list without erroring', function()
      assert.has_no.errors(function()
        ui.render_results(layout, {}, entry_to_string, 1)
      end)
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(layout.results_buf, 0, -1, false))
    end)

    it('highlights fuzzy-match positions with MepMatch extmarks', function()
      local results = {
        { item = { name = 'init.lua' }, positions = { 1, 2 } },
      }
      ui.render_results(layout, results, entry_to_string, 1)

      local ns = vim.api.nvim_get_namespaces()['mep_picker_matches']
      assert.is_not_nil(ns)
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, {})
      assert.are.equal(2, #marks)
    end)

    it('leaves results_buf unmodifiable after rendering', function()
      ui.render_results(layout, {}, entry_to_string, 1)
      assert.is_false(vim.bo[layout.results_buf].modifiable)
    end)

    -- 'cursorline' (set on the results window at create_layout time)
    -- only ever renders in the *focused* window, and the results window
    -- never actually receives focus (mep.picker.engine's own next/prev/
    -- select keymaps stay on the prompt window throughout) — so the
    -- selected row needs its own explicit, focus-independent highlight.
    it('marks the selected row with an explicit MepPickerSelected extmark', function()
      local results = {
        { item = { name = 'a' } },
        { item = { name = 'b' } },
        { item = { name = 'c' } },
      }
      ui.render_results(layout, results, entry_to_string, 2)

      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      assert.is_not_nil(ns)
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2]) -- row 2 (1-based) -> 0-based extmark row 1
      assert.are.equal('MepPickerSelected', marks[1][4].hl_group)
    end)

    it('moves the mark, not adds a second one, on re-render', function()
      local results = {
        { item = { name = 'a' } },
        { item = { name = 'b' } },
      }
      ui.render_results(layout, results, entry_to_string, 1)
      ui.render_results(layout, results, entry_to_string, 2)

      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2])
    end)

    it('clears the mark for an empty result list', function()
      ui.render_results(layout, { { item = { name = 'a' } } }, entry_to_string, 1)
      ui.render_results(layout, {}, entry_to_string, 1)

      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)
  end)

  describe('mark_selected', function()
    local layout

    before_each(function()
      layout = ui.create_layout({ title = 'Test' })
      vim.api.nvim_buf_set_lines(layout.results_buf, 0, -1, false, { 'a', 'b', 'c' })
    end)

    after_each(function()
      ui.close_layout(layout)
    end)

    it('is callable directly (Picker:move\'s own use, without a full re-render)', function()
      ui.mark_selected(layout, 3)
      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
      assert.are.equal(2, marks[1][2])
    end)

    it('clears the mark when given nil', function()
      ui.mark_selected(layout, 1)
      ui.mark_selected(layout, nil)
      local ns = vim.api.nvim_get_namespaces()['mep_picker_selected']
      local marks = vim.api.nvim_buf_get_extmarks(layout.results_buf, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)

    it('is a no-op on an invalid buffer', function()
      ui.close_layout(layout)
      assert.has_no.errors(function()
        ui.mark_selected(layout, 1)
      end)
    end)
  end)
end)

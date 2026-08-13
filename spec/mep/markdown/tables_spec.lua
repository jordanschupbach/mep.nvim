-- Pure line-pattern matching + extmarks, no subprocess involved (see
-- spec/README.md) — real buffers are fine here.
local tables = require('mep.markdown.tables')

describe('mep.markdown.tables', function()
  local ns
  local created_bufs

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    created_bufs[#created_bufs + 1] = bufnr
    return bufnr
  end

  local function extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end

  before_each(function()
    ns = vim.api.nvim_create_namespace('mep_markdown_tables')
    created_bufs = {}
  end)

  after_each(function()
    tables._reset()
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  describe('find_tables', function()
    it('finds a simple header + separator + one row table', function()
      local found = tables.find_tables({
        '| Name | Age |',
        '| --- | --- |',
        '| Alice | 30 |',
        '',
      })
      assert.are.equal(1, #found)
      local t = found[1]
      assert.are.equal(1, t.start_line)
      assert.are.equal(3, t.end_line)
      assert.are.same({ 'Name', 'Age' }, t.header)
      assert.are.same({ 'left', 'left' }, t.aligns)
      assert.are.same({ { 'Alice', '30' } }, t.rows)
    end)

    it('parses left/center/right alignment markers', function()
      local found = tables.find_tables({
        '| A | B | C |',
        '| :-- | :-: | --: |',
        '| 1 | 2 | 3 |',
      })
      assert.are.same({ 'left', 'center', 'right' }, found[1].aligns)
    end)

    it('is a no-op without pipes at all', function()
      assert.are.same({}, tables.find_tables({ 'just', 'plain', 'prose' }))
    end)

    it('rejects a header line not followed by a valid separator', function()
      assert.are.same({}, tables.find_tables({ '| Name | Age |', 'not a separator' }))
    end)

    it('stops the table at the first blank line', function()
      local found = tables.find_tables({
        '| A |',
        '| - |',
        '| 1 |',
        '',
        '| B |',
        '| - |',
        '| 2 |',
      })
      assert.are.equal(2, #found)
      assert.are.equal(3, found[1].end_line)
      assert.are.equal(5, found[2].start_line)
    end)

    it('finds two tables separated by prose', function()
      local found = tables.find_tables({
        '| A |',
        '| - |',
        '| 1 |',
        'some text',
        '| B |',
        '| - |',
        '| 2 |',
      })
      assert.are.equal(2, #found)
    end)

    it('works with no outer pipes on rows', function()
      local found = tables.find_tables({
        'A | B',
        '- | -',
        '1 | 2',
      })
      assert.are.equal(1, #found)
      assert.are.same({ 'A', 'B' }, found[1].header)
      assert.are.same({ { '1', '2' } }, found[1].rows)
    end)
  end)

  describe('compute_widths', function()
    it('is the max display width per column, at least 3', function()
      local t = tables.find_tables({
        '| a | wide-column |',
        '| - | - |',
        '| x | y |',
      })[1]
      assert.are.same({ 3, 11 }, tables.compute_widths(t))
    end)
  end)

  describe('attach', function()
    it('overlays the header, separator, and row lines of a detected table', function()
      local bufnr = make_buf({ '| Name | Age |', '| --- | --- |', '| Alice | 30 |' })
      tables.attach(bufnr)

      local marks = extmarks(bufnr)
      local rows = {}
      for _, m in ipairs(marks) do
        if m[4].virt_text then
          rows[m[2]] = true
        end
      end
      assert.is_true(rows[0]) -- header
      assert.is_true(rows[1]) -- separator
      assert.is_true(rows[2]) -- data row
    end)

    it('adds virt_lines borders above the header and below the last row', function()
      local bufnr = make_buf({ '| A |', '| - |', '| 1 |' })
      tables.attach(bufnr)

      local has_top, has_bottom = false, false
      for _, m in ipairs(extmarks(bufnr)) do
        if m[4].virt_lines then
          if m[4].virt_lines_above then
            has_top = true
          else
            has_bottom = true
          end
        end
      end
      assert.is_true(has_top)
      assert.is_true(has_bottom)
    end)

    it('does not overlay a buffer with no tables', function()
      local bufnr = make_buf({ 'just', 'plain', 'prose' })
      tables.attach(bufnr)
      assert.are.same({}, extmarks(bufnr))
    end)

    it('leaves the row the cursor is on un-overlaid', function()
      local bufnr = make_buf({ '| Name | Age |', '| --- | --- |', '| Alice | 30 |' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- the data row
      tables.attach(bufnr)

      local overlaid_row2 = false
      for _, m in ipairs(extmarks(bufnr)) do
        if m[2] == 2 and m[4].virt_text then
          overlaid_row2 = true
        end
      end
      assert.is_false(overlaid_row2)
    end)

    it('reveals the previous row and hides the new one as the cursor moves', function()
      local bufnr = make_buf({ '| Name | Age |', '| --- | --- |', '| Alice | 30 |' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      tables.attach(bufnr)

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = bufnr })

      local row0, row2 = false, false
      for _, m in ipairs(extmarks(bufnr)) do
        if m[4].virt_text and m[2] == 0 then
          row0 = true
        end
        if m[4].virt_text and m[2] == 2 then
          row2 = true
        end
      end
      assert.is_true(row0) -- header, no longer under the cursor
      assert.is_false(row2) -- data row, now under the cursor
    end)

    it('is idempotent: attaching an already-attached buffer is a no-op', function()
      local bufnr = make_buf({ '| A |', '| - |' })
      tables.attach(bufnr)
      tables.attach(bufnr)
      assert.is_true(tables.is_attached(bufnr))
    end)

    it('recomputes (debounced) on TextChanged', function()
      local bufnr = make_buf({ 'no table here' })
      tables.attach(bufnr)
      assert.are.same({}, extmarks(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '| A |', '| - |', '| 1 |' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })

      vim.wait(500, function()
        return #extmarks(bufnr) > 0
      end, 10)
      assert.is_true(#extmarks(bufnr) > 0)
    end)
  end)

  describe('detach', function()
    it('clears extmarks and stops tracking', function()
      local bufnr = make_buf({ '| A |', '| - |', '| 1 |' })
      tables.attach(bufnr)
      tables.detach(bufnr)
      assert.are.same({}, extmarks(bufnr))
      assert.is_false(tables.is_attached(bufnr))
    end)

    it('is triggered automatically on BufWipeout', function()
      local bufnr = make_buf({ '| A |', '| - |' })
      tables.attach(bufnr)
      vim.cmd('bwipeout! ' .. bufnr)
      assert.is_false(tables.is_attached(bufnr))
    end)
  end)

  describe('_reset', function()
    it('detaches every currently tracked buffer', function()
      local a = make_buf({ '| A |', '| - |' })
      local b = make_buf({ '| B |', '| - |' })
      tables.attach(a)
      tables.attach(b)
      tables._reset()
      assert.is_false(tables.is_attached(a))
      assert.is_false(tables.is_attached(b))
    end)
  end)
end)

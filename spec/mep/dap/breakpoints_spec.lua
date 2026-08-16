local breakpoints = require('mep.dap.breakpoints')

local ns = vim.api.nvim_create_namespace('mep_dap_breakpoints')

describe('mep.dap.breakpoints', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/mep-dap-breakpoints-' .. bufnr .. '.py')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four', 'five' })
  end)

  after_each(function()
    breakpoints.clear_all()
    breakpoints.detach(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('toggle/list', function()
    it('adds a breakpoint and reports it in list()', function()
      local now_set = breakpoints.toggle(bufnr, 2)
      assert.is_true(now_set)
      assert.are.same({ 2 }, breakpoints.list(bufnr))
    end)

    it('removes a breakpoint on a second toggle', function()
      breakpoints.toggle(bufnr, 2)
      local now_set = breakpoints.toggle(bufnr, 2)
      assert.is_false(now_set)
      assert.are.same({}, breakpoints.list(bufnr))
    end)

    it('keeps multiple breakpoints sorted', function()
      breakpoints.toggle(bufnr, 4)
      breakpoints.toggle(bufnr, 1)
      breakpoints.toggle(bufnr, 3)
      assert.are.same({ 1, 3, 4 }, breakpoints.list(bufnr))
    end)

    it('returns false and records nothing for an unnamed buffer', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      local now_set = breakpoints.toggle(scratch, 1)
      assert.is_false(now_set)
      assert.are.same({}, breakpoints.list(scratch))
      vim.api.nvim_buf_delete(scratch, { force = true })
    end)
  end)

  describe('clear', function()
    it('removes every breakpoint for the buffer', function()
      breakpoints.toggle(bufnr, 1)
      breakpoints.toggle(bufnr, 2)
      breakpoints.clear(bufnr)
      assert.are.same({}, breakpoints.list(bufnr))
    end)
  end)

  describe('clear_all', function()
    it('removes breakpoints across every file', function()
      local other = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(other, '/tmp/mep-dap-breakpoints-other-' .. other .. '.py')
      breakpoints.toggle(bufnr, 1)
      breakpoints.toggle(other, 1)

      breakpoints.clear_all()

      assert.are.same({}, breakpoints.list(bufnr))
      assert.are.same({}, breakpoints.list(other))
      vim.api.nvim_buf_delete(other, { force = true })
    end)
  end)

  describe('all', function()
    it('lists every path with its sorted line numbers', function()
      breakpoints.toggle(bufnr, 3)
      breakpoints.toggle(bufnr, 1)
      local all = breakpoints.all()
      local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p')
      local entry
      for _, e in ipairs(all) do
        if e.path == path then
          entry = e
        end
      end
      assert.is_not_nil(entry)
      assert.are.same({ 1, 3 }, entry.lnums)
    end)
  end)

  describe('on_change', function()
    it('notifies listeners with the path and current lnums after toggle', function()
      local seen
      breakpoints.on_change(function(path, lnums)
        seen = { path = path, lnums = lnums }
      end)
      breakpoints.toggle(bufnr, 5)
      assert.is_not_nil(seen)
      assert.are.same({ 5 }, seen.lnums)
      assert.are.equal(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p'), seen.path)
    end)
  end)

  describe('render', function()
    it('places one sign extmark per breakpoint', function()
      breakpoints.toggle(bufnr, 1)
      breakpoints.toggle(bufnr, 3)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.are.equal(2, #marks)
      local rows = {}
      for _, m in ipairs(marks) do
        rows[#rows + 1] = m[2]
      end
      table.sort(rows)
      assert.are.same({ 0, 2 }, rows) -- 0-indexed rows for lines 1 and 3
    end)

    it('skips a breakpoint line beyond the current buffer length', function()
      breakpoints.toggle(bufnr, 1)
      breakpoints.toggle(bufnr, 999)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(1, #marks)
    end)
  end)

  describe('attach/detach', function()
    it('renders signs immediately on attach', function()
      breakpoints.toggle(bufnr, 2)
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      breakpoints.attach(bufnr)
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(1, #marks)
    end)

    it('re-renders on BufReadPost after detach + a fresh attach', function()
      breakpoints.toggle(bufnr, 2)
      breakpoints.attach(bufnr)
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      vim.api.nvim_exec_autocmds('BufReadPost', { buffer = bufnr })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.equal(1, #marks)
    end)

    it('stops re-rendering after detach', function()
      breakpoints.toggle(bufnr, 2)
      breakpoints.attach(bufnr)
      breakpoints.detach(bufnr)
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      vim.api.nvim_exec_autocmds('BufReadPost', { buffer = bufnr })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.are.same({}, marks)
    end)
  end)

  describe('define_default_hl', function()
    it('defines MepDapBreakpoint', function()
      assert.are.equal(1, vim.fn.hlexists('MepDapBreakpoint'))
    end)
  end)
end)

-- Pure buffer-text scanning, no jobs involved — but attach() only ever
-- tracks a normal (buftype == '') buffer, the same guard mep.git.
-- gutter.attach uses, so tests use ordinary listed buffers rather than
-- scratch ones (buftype 'nofile').
local highlight = require('mep.todoscan.highlight')
local config = require('mep.todoscan.config')

describe('mep.todoscan.highlight', function()
  local saved_options
  local created_bufs

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    config.setup({ debounce_ms = 5 })
    created_bufs = {}
  end)

  after_each(function()
    highlight._reset()
    config.options = saved_options
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    created_bufs[#created_bufs + 1] = bufnr
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  local function extmarks(bufnr)
    local ns = vim.api.nvim_create_namespace('mep_todoscan')
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  end

  describe('hl_group', function()
    it('title-cases a keyword into MepTodoScan<Keyword>', function()
      assert.are.equal('MepTodoScanTodo', highlight.hl_group('TODO'))
      assert.are.equal('MepTodoScanFixme', highlight.hl_group('FIXME'))
    end)
  end)

  describe('attach / recompute', function()
    it('places a sign and highlight extmark on a matching line', function()
      local bufnr = make_buf({ 'first', '-- TODO fix this', 'last' })
      highlight.attach(bufnr)
      local marks = extmarks(bufnr)
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2]) -- 0-indexed row 1 ("-- TODO fix this")
      assert.are.equal('TD', marks[1][4].sign_text)
      assert.are.equal('MepTodoScanTodo', marks[1][4].sign_hl_group)
    end)

    it('places nothing when no line matches', function()
      local bufnr = make_buf({ 'nothing', 'to see here' })
      highlight.attach(bufnr)
      assert.are.same({}, extmarks(bufnr))
    end)

    it('is a no-op for a non-normal (scratch) buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      created_bufs[#created_bufs + 1] = bufnr
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'TODO here' })
      highlight.attach(bufnr)
      assert.are.same({}, extmarks(bufnr))
    end)

    it('is a no-op when called twice on the same buffer', function()
      local bufnr = make_buf({ 'TODO here' })
      highlight.attach(bufnr)
      local first_marks = extmarks(bufnr)
      highlight.attach(bufnr)
      assert.are.equal(#first_marks, #extmarks(bufnr))
    end)

    it('recomputes (debounced) on TextChanged', function()
      local bufnr = make_buf({ 'nothing here' })
      highlight.attach(bufnr)
      assert.are.same({}, extmarks(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'TODO now' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })

      vim.wait(500, function()
        return #extmarks(bufnr) == 1
      end, 10)
      assert.are.equal(1, #extmarks(bufnr))
    end)

    it('honors a custom keyword list', function()
      config.setup({ keywords = { 'XXX' }, debounce_ms = 5 })
      local bufnr = make_buf({ 'TODO ignored', 'XXX matched' })
      highlight.attach(bufnr)
      local marks = extmarks(bufnr)
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2])
    end)

    it('uses a configured sign override', function()
      config.setup({ signs = { TODO = '!!' }, debounce_ms = 5 })
      local bufnr = make_buf({ 'TODO here' })
      highlight.attach(bufnr)
      assert.are.equal('!!', extmarks(bufnr)[1][4].sign_text)
    end)

    it('falls back to the first two letters, uppercased, for an unconfigured custom keyword', function()
      config.setup({ keywords = { 'perf' }, debounce_ms = 5 })
      local bufnr = make_buf({ 'perf: slow path' })
      highlight.attach(bufnr)
      assert.are.equal('PE', extmarks(bufnr)[1][4].sign_text)
    end)
  end)

  describe('detach', function()
    it('clears signs/highlights and stops recomputing', function()
      local bufnr = make_buf({ 'TODO here' })
      highlight.attach(bufnr)
      assert.are.equal(1, #extmarks(bufnr))

      highlight.detach(bufnr)
      assert.are.same({}, extmarks(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'FIXME too' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
      vim.wait(50, function()
        return false
      end, 10)
      assert.are.same({}, extmarks(bufnr))
    end)

    it('is a no-op for a buffer that was never attached', function()
      local bufnr = make_buf({ 'TODO here' })
      assert.has_no.errors(function()
        highlight.detach(bufnr)
      end)
    end)
  end)

  describe('enable / disable', function()
    it('attaches every already-loaded normal buffer', function()
      local bufnr = make_buf({ 'TODO here' })
      highlight.enable()
      assert.are.equal(1, #extmarks(bufnr))
    end)

    it('attaches a buffer entered after enable() via BufEnter', function()
      highlight.enable()
      local bufnr = make_buf({ 'TODO here' })
      vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })
      assert.are.equal(1, #extmarks(bufnr))
    end)

    it('disable detaches every attached buffer', function()
      local bufnr = make_buf({ 'TODO here' })
      highlight.enable()
      assert.are.equal(1, #extmarks(bufnr))
      highlight.disable()
      assert.are.same({}, extmarks(bufnr))
    end)
  end)
end)

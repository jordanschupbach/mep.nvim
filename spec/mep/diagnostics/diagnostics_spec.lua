local diagnostics = require('mep.diagnostics')
local config = require('mep.diagnostics.config')

local diag_ns = vim.api.nvim_create_namespace('mep_diagnostics_spec_test')
local ns = vim.api.nvim_create_namespace('mep_diagnostics_circles')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function set_diags(buf, diags)
  vim.diagnostic.set(diag_ns, buf, diags)
end

describe('mep.diagnostics', function()
  local saved_options
  local orig_diag_config

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_diag_config = vim.diagnostic.config
  end)

  after_each(function()
    diagnostics._reset()
    config.options = saved_options
    vim.diagnostic.config = orig_diag_config
    pcall(vim.keymap.del, 'n', '<leader>ld')
    pcall(vim.keymap.del, 'n', '<localleader>ld1')
  end)

  describe('apply / clear', function()
    it('places one circle per diagnostic-bearing line', function()
      local buf = make_buf({ 'a', 'b', 'c' })
      set_diags(buf, {
        { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN, message = 'meh' },
      })

      diagnostics.apply(buf)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.are.equal(2, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('picks the highest-severity color when a line has multiple diagnostics', function()
      local buf = make_buf({ 'a' })
      set_diags(buf, {
        { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = 'meh' },
        { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' },
      })

      diagnostics.apply(buf)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      assert.are.equal('DiagnosticError', marks[1][4].virt_text[1][2])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('clear() removes every circle extmark', function()
      local buf = make_buf({ 'a' })
      set_diags(buf, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' } })
      diagnostics.apply(buf)
      diagnostics.clear(buf)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(0, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('a fresh apply() replaces stale circles rather than accumulating them', function()
      local buf = make_buf({ 'a' })
      set_diags(buf, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' } })
      diagnostics.apply(buf)
      diagnostics.apply(buf)
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('show_line_float', function()
    it('opens vim.diagnostic.open_float scoped to the given line', function()
      local buf = make_buf({ 'a' })
      local seen_bufnr, seen_opts
      local orig_open_float = vim.diagnostic.open_float
      vim.diagnostic.open_float = function(bufnr, opts)
        seen_bufnr, seen_opts = bufnr, opts
      end

      diagnostics.show_line_float(buf, 3)

      assert.are.equal(buf, seen_bufnr)
      assert.are.equal('line', seen_opts.scope)
      assert.are.same({ 3, 0 }, seen_opts.pos)
      assert.are.equal('rounded', seen_opts.border)

      vim.diagnostic.open_float = orig_open_float
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('setup', function()
    it('forces virtual_text off when enabled', function()
      local seen
      vim.diagnostic.config = function(opts)
        seen = opts
      end
      diagnostics.setup({ keymaps = { show_line = { '<localleader>ld1' } } })
      assert.is_false(seen.virtual_text)
    end)

    it('leaves vim.diagnostic.config untouched when disabled', function()
      local called = false
      vim.diagnostic.config = function()
        called = true
      end
      diagnostics.setup({ enable = false })
      assert.is_false(called)
    end)

    it('binds the configured show_line keymap', function()
      diagnostics.setup({ keymaps = { show_line = { '<localleader>ld1' } } })
      local found = false
      for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
        if m.lhs == vim.api.nvim_replace_termcodes('<localleader>ld1', true, false, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('recomputes circles on DiagnosticChanged', function()
      diagnostics.setup({ keymaps = { show_line = { '<localleader>ld1' } } })
      local buf = make_buf({ 'a' })
      set_diags(buf, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'bad' } })
      vim.api.nvim_exec_autocmds('DiagnosticChanged', { buffer = buf })

      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

local todoscan = require('mep.todoscan')
local config = require('mep.todoscan.config')
local highlight = require('mep.todoscan.highlight')

describe('mep.todoscan', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
    highlight._reset()
  end)

  describe('picker', function()
    it('starts a picker built from mep.todoscan.picker.picker_opts', function()
      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local seen
      picker_mod.start = function(opts)
        seen = opts
      end

      todoscan.picker({ cwd = '/repo' })

      picker_mod.start = orig_start
      assert.is_not_nil(seen)
      assert.matches('TODO Scan', seen.prompt_title)
    end)
  end)

  describe('setup', function()
    it('enables live highlighting by default', function()
      todoscan.setup({})
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'TODO here' })
      vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })
      local ns = vim.api.nvim_create_namespace('mep_todoscan')
      assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    it('does not enable live highlighting when highlight = false', function()
      todoscan.setup({ highlight = false })
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'TODO here' })
      vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })
      local ns = vim.api.nvim_create_namespace('mep_todoscan')
      assert.are.same({}, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    it('returns the resolved options', function()
      local options = todoscan.setup({ keywords = { 'XXX' }, highlight = false })
      assert.are.same({ 'XXX' }, options.keywords)
    end)
  end)
end)

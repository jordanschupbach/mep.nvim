local scratch = require('mep.scratch')
local config = require('mep.scratch.config')

describe('mep.scratch', function()
  local saved_options
  local other_buf

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    other_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(other_buf)
  end)

  after_each(function()
    scratch.reset()
    config.options = saved_options
    if vim.api.nvim_buf_is_valid(other_buf) then
      pcall(vim.api.nvim_buf_delete, other_buf, { force = true })
    end
  end)

  describe('open', function()
    it('switches the current window to a new buftype=nofile buffer', function()
      scratch.open()
      local buf = vim.api.nvim_get_current_buf()
      assert.are_not.equal(other_buf, buf)
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.are.equal('hide', vim.bo[buf].bufhidden)
      assert.is_false(vim.bo[buf].swapfile)
    end)

    it('names the buffer from config.options.name', function()
      config.setup({ name = 'my-notes' })
      scratch.open()
      assert.matches('my%-notes$', vim.api.nvim_buf_get_name(0))
    end)

    it('leaves filetype unset by default', function()
      scratch.open()
      assert.are.equal('', vim.bo[0].filetype)
    end)

    it('sets filetype from config.options.filetype when configured', function()
      config.setup({ filetype = 'markdown' })
      scratch.open()
      assert.are.equal('markdown', vim.bo[0].filetype)
    end)

    it('reuses the same buffer (and its content) on a second call', function()
      scratch.open()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello', 'world' })

      vim.api.nvim_set_current_buf(other_buf)
      scratch.open()

      assert.are.equal(buf, vim.api.nvim_get_current_buf())
      assert.are.same({ 'hello', 'world' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('creates a fresh buffer if the previous one was wiped out from under it', function()
      scratch.open()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_buf(other_buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      scratch.open()

      local new_buf = vim.api.nvim_get_current_buf()
      assert.are_not.equal(buf, new_buf)
      assert.are.equal('nofile', vim.bo[new_buf].buftype)
    end)
  end)

  describe('reset', function()
    it('wipes the scratch buffer so the next open() starts empty', function()
      scratch.open()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'stale content' })

      scratch.reset()
      assert.is_false(vim.api.nvim_buf_is_valid(buf))

      scratch.open()
      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it('is a no-op before open() has ever been called', function()
      assert.has_no.errors(function()
        scratch.reset()
      end)
    end)
  end)
end)

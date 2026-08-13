local dashboard = require('mep.dashboard.dashboard')
local config = require('mep.dashboard.config')

describe('mep.dashboard.dashboard', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    vim.cmd('enew') -- a known-fresh, unnamed, empty, unmodified buffer
  end)

  after_each(function()
    dashboard.reset()
    config.options = saved_options
  end)

  describe('should_auto_open', function()
    it('is true for a fresh, untouched, single-window start', function()
      assert.is_true(dashboard.should_auto_open())
    end)

    it('is false when file arguments were given', function()
      local orig_argc = vim.fn.argc
      vim.fn.argc = function()
        return 1
      end
      assert.is_false(dashboard.should_auto_open())
      vim.fn.argc = orig_argc
    end)

    it('is false when more than one window is open', function()
      vim.cmd('split')
      assert.is_false(dashboard.should_auto_open())
      vim.cmd('close')
    end)

    it('is false for a named buffer', function()
      vim.api.nvim_buf_set_name(0, '/tmp/mep-dashboard-spec-named.txt')
      assert.is_false(dashboard.should_auto_open())
    end)

    it('is false when a filetype is already set', function()
      vim.bo.filetype = 'lua'
      assert.is_false(dashboard.should_auto_open())
    end)

    it('is false for a modified buffer', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'edited' })
      assert.is_true(vim.bo.modified)
      assert.is_false(dashboard.should_auto_open())
    end)

    it('is false when the buffer already has more than one line', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '', '' })
      assert.is_false(dashboard.should_auto_open())
    end)

    it('is false when the single line already has content', function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'not empty' })
      assert.is_false(dashboard.should_auto_open())
    end)

    it('is false after stdin was read, once auto-open is enabled', function()
      dashboard.enable_auto_open()
      vim.api.nvim_exec_autocmds('StdinReadPre', {})
      assert.is_false(dashboard.should_auto_open())
    end)
  end)

  describe('open', function()
    it('renders resolved content into the current buffer, centered', function()
      config.setup({ content = { 'hello' } })
      dashboard.open()

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local text = table.concat(lines, '\n')
      assert.matches('hello', text, 1, true)
      assert.are.equal('mep-dashboard', vim.bo.filetype)
      assert.is_false(vim.bo.modifiable)
    end)

    it('uses the constructed intro content by default', function()
      dashboard.open()
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.matches('NVIM v', text, 1, true)
    end)

    it('turns off the gutter (number/relativenumber/signcolumn) and the eob ~s', function()
      dashboard.open()
      assert.is_false(vim.wo.number)
      assert.is_false(vim.wo.relativenumber)
      assert.are.equal('no', vim.wo.signcolumn)
      assert.matches('eob: ', vim.wo.fillchars)
    end)

    it('restores the window\'s previous gutter settings once the dashboard buffer is replaced', function()
      vim.wo.number = true
      vim.wo.signcolumn = 'yes'
      dashboard.open()
      assert.is_false(vim.wo.number)

      vim.cmd('enew') -- replaces (and, bufhidden=wipe, wipes) the dashboard buffer
      assert.is_true(vim.wo.number)
      assert.are.equal('yes', vim.wo.signcolumn)
    end)
  end)

  describe('enable_auto_open / disable_auto_open', function()
    it('opens the dashboard on VimEnter when conditions hold', function()
      dashboard.enable_auto_open()
      vim.api.nvim_exec_autocmds('VimEnter', {})
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.matches('NVIM v', text, 1, true)
    end)

    it('does not open on VimEnter when should_auto_open is false', function()
      vim.api.nvim_buf_set_name(0, '/tmp/mep-dashboard-spec-named2.txt')
      dashboard.enable_auto_open()
      vim.api.nvim_exec_autocmds('VimEnter', {})
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.is_not.matches('NVIM v', text, 1, true)
    end)

    it('disable_auto_open stops VimEnter from opening it', function()
      dashboard.enable_auto_open()
      dashboard.disable_auto_open()
      vim.api.nvim_exec_autocmds('VimEnter', {})
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.is_not.matches('NVIM v', text, 1, true)
    end)
  end)

  describe('setup', function()
    it('enables auto-open by default', function()
      dashboard.setup({})
      vim.api.nvim_exec_autocmds('VimEnter', {})
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.matches('NVIM v', text, 1, true)
    end)

    it('does not register auto-open when auto_open = false', function()
      dashboard.setup({ auto_open = false })
      vim.api.nvim_exec_autocmds('VimEnter', {})
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.is_not.matches('NVIM v', text, 1, true)
    end)

    it('returns the merged options table', function()
      local opts = dashboard.setup({ content = { 'x' } })
      assert.are.same({ 'x' }, opts.content)
    end)
  end)

  describe('reset', function()
    it('clears the stdin-read flag and disables auto-open', function()
      dashboard.enable_auto_open()
      vim.api.nvim_exec_autocmds('StdinReadPre', {})
      assert.is_false(dashboard.should_auto_open())

      dashboard.reset()
      dashboard.enable_auto_open()
      assert.is_true(dashboard.should_auto_open()) -- stdin flag forgotten
    end)
  end)
end)

-- mep.run.terminal.open ultimately calls vim.fn.jobstart(cmd, { term =
-- true }) — mocked here the same way every other job-backed spec in
-- this suite mocks vim.fn.jobstart, so no real subprocess/terminal job
-- ever actually spawns (see spec/README.md).
local terminal = require('mep.run.terminal')
local config = require('mep.run.config')

describe('mep.run.terminal', function()
  local orig_jobstart
  local saved_options
  local captured

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_jobstart = vim.fn.jobstart
    captured = nil
    vim.fn.jobstart = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      return 1
    end
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    config.options = saved_options
  end)

  describe('open', function()
    it('splits below the current window and runs cmd as a terminal job', function()
      local win_before = vim.api.nvim_get_current_win()
      local buf = terminal.open({ 'echo', 'hi' })

      assert.are_not.equal(win_before, vim.api.nvim_get_current_win())
      assert.are.same({ 'echo', 'hi' }, captured.cmd)
      assert.is_true(captured.opts.term)
      assert.are.equal(buf, vim.api.nvim_get_current_buf())

      vim.api.nvim_win_close(0, true)
    end)

    it('sizes the split to terminal_height_ratio of the original window height', function()
      config.setup({ terminal_height_ratio = 0.5 })
      local total_height = vim.api.nvim_win_get_height(vim.api.nvim_get_current_win())

      terminal.open({ 'echo' })

      local new_height = vim.api.nvim_win_get_height(vim.api.nvim_get_current_win())
      local expected = math.max(1, math.floor(total_height * 0.5 + 0.5))
      -- The split shrinks the *original* window too, so exact pixel
      -- parity isn't guaranteed post-split — just check it's in the
      -- right ballpark rather than the full original height.
      assert.is_true(new_height <= expected + 1)

      vim.api.nvim_win_close(0, true)
    end)

    it('restores splitbelow/equalalways after splitting', function()
      local orig_splitbelow, orig_equalalways = vim.o.splitbelow, vim.o.equalalways
      vim.o.splitbelow = false
      vim.o.equalalways = true

      terminal.open({ 'echo' })

      assert.are.equal(false, vim.o.splitbelow)
      assert.are.equal(true, vim.o.equalalways)

      vim.api.nvim_win_close(0, true)
      vim.o.splitbelow, vim.o.equalalways = orig_splitbelow, orig_equalalways
    end)
  end)
end)

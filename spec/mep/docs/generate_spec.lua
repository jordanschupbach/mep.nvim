local generate = require('mep.docs.generate')
local lsp = require('mep.docs.lsp')

describe('mep.docs.generate', function()
  local bufnr, win
  local orig_lsp_request

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(bufnr, true, { relative = 'editor', row = 0, col = 0, width = 40, height = 10 })
    orig_lsp_request = lsp.request
  end)

  after_each(function()
    lsp.request = orig_lsp_request
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function no_lsp_client()
    lsp.request = function(_, _, callback)
      callback(nil, nil)
    end
  end

  describe('generate (fallback parser path — no LSP client)', function()
    before_each(no_lsp_client)

    it('inserts a below-position skeleton (python) indented one level deeper than the def line', function()
      vim.bo[bufnr].filetype = 'python'
      vim.bo[bufnr].expandtab = true
      vim.bo[bufnr].shiftwidth = 4
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'def add(x, y):', '    pass' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      generate.generate(bufnr, win)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are.equal('def add(x, y):', lines[1])
      assert.matches('^    """TODO: describe add%.', lines[2])
      -- the original body line is still there, after the inserted skeleton
      assert.matches('pass', lines[#lines])
    end)

    it('inserts an above-position skeleton (lua) at the same indentation as the function line', function()
      vim.bo[bufnr].filetype = 'lua'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '  function M.add(a, b)', '    return a + b', '  end' })
      vim.api.nvim_win_set_cursor(win, { 1, 2 })

      generate.generate(bufnr, win)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.matches('^  %-%-%- TODO: describe M%.add%.', lines[1])
      local fn_line_idx
      for i, l in ipairs(lines) do
        if l:match('function M%.add') then
          fn_line_idx = i
        end
      end
      assert.are.equal('  function M.add(a, b)', lines[fn_line_idx])
    end)

    it('notifies and inserts nothing for a filetype with no docstring template', function()
      vim.bo[bufnr].filetype = 'brainfuck'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '+++.' })
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      generate.generate(bufnr, win)
      vim.notify = orig_notify

      assert.matches('no docstring template', notified)
      assert.are.same({ '+++.' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('notifies and inserts nothing when no function signature is found on the cursor line', function()
      vim.bo[bufnr].filetype = 'python'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x = 1' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      generate.generate(bufnr, win)
      vim.notify = orig_notify

      assert.matches('no function signature', notified)
      assert.are.same({ 'x = 1' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    end)

    it('uses tabs for below-position indentation when noexpandtab', function()
      vim.bo[bufnr].filetype = 'python'
      vim.bo[bufnr].expandtab = false
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'def add(x):' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      generate.generate(bufnr, win)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.matches('^\t"""', lines[2])
    end)
  end)

  describe('generate (LSP path)', function()
    it('uses the LSP-provided name/params instead of parsing the line', function()
      lsp.request = function(_, _, callback)
        callback('real_name', { 'real_param' })
      end
      vim.bo[bufnr].filetype = 'python'
      -- The line itself doesn't even look like a function — proves the
      -- LSP-provided values are what actually got used, not a fallback
      -- parse of this line.
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x = 1' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      generate.generate(bufnr, win)

      local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
      assert.matches('describe real_name', text)
      assert.matches('real_param: TODO', text)
    end)
  end)
end)

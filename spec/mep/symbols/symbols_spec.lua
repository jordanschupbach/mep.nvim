local symbols = require('mep.symbols.symbols')
local config = require('mep.symbols.config')

local function range(start_line, start_char, end_line, end_char)
  return {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line, character = end_char },
  }
end

local function make_client(responder)
  return {
    name = 'test_ls',
    request = function(_, _method, _params, handler, bufnr)
      responder(handler, bufnr)
    end,
  }
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.symbols.symbols', function()
  local saved_options
  local orig_get_clients, orig_make_text_document_params

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_get_clients = vim.lsp.get_clients
    orig_make_text_document_params = vim.lsp.util.make_text_document_params
    vim.lsp.util.make_text_document_params = function()
      return { uri = 'file:///test' }
    end
    vim.lsp.get_clients = function()
      return {}
    end
  end)

  after_each(function()
    symbols.close()
    config.options = saved_options
    vim.lsp.get_clients = orig_get_clients
    vim.lsp.util.make_text_document_params = orig_make_text_document_params
    pcall(vim.keymap.del, 'n', '<leader>ll')
    pcall(vim.keymap.del, 'n', '<leader>o')
  end)

  local function respond_with(symbol_list)
    vim.lsp.get_clients = function()
      return {
        make_client(function(handler)
          handler(nil, symbol_list)
        end),
      }
    end
  end

  describe('open / close / toggle / is_open', function()
    it('is closed until opened', function()
      assert.is_false(symbols.is_open())
    end)

    it('open() opens a real split window', function()
      symbols.open()
      assert.is_true(symbols.is_open())
    end)

    it('open() is a no-op if already open', function()
      symbols.open()
      local win_before = symbols.is_open() and vim.api.nvim_get_current_win() or nil
      symbols.open()
      assert.are.equal(win_before, vim.api.nvim_get_current_win())
    end)

    it('close() closes the window', function()
      symbols.open()
      symbols.close()
      assert.is_false(symbols.is_open())
    end)

    it('close() is a no-op if not open', function()
      assert.has_no.errors(function()
        symbols.close()
      end)
    end)

    it('toggle() opens when closed and closes when open', function()
      symbols.toggle()
      assert.is_true(symbols.is_open())
      symbols.toggle()
      assert.is_false(symbols.is_open())
    end)
  end)

  describe('sizing', function()
    it('sizes the split to width_ratio of the current window, at least min_width', function()
      config.setup({ width_ratio = 0.25, min_width = 5 })
      vim.cmd('only')
      local target_width = vim.api.nvim_win_get_width(0)

      symbols.open()
      local win = vim.api.nvim_get_current_win()
      assert.are.equal(math.max(5, math.floor(target_width * 0.25)), vim.api.nvim_win_get_width(win))
    end)

    it('never shrinks below min_width', function()
      config.setup({ width_ratio = 0.01, min_width = 17 })
      symbols.open()
      local win = vim.api.nvim_get_current_win()
      assert.are.equal(17, vim.api.nvim_win_get_width(win))
    end)
  end)

  describe('rendering', function()
    it('shows a loading message immediately, then the request result', function()
      respond_with({ { name = 'Foo', kind = 5, range = range(0, 0, 0, 3) } })
      symbols.open()
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('Foo') ~= nil
      end, 10)

      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('%[Class%] Foo', text)
    end)

    it('shows a message instead of erroring when no client is attached', function()
      vim.lsp.get_clients = function()
        return {}
      end
      symbols.open()
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      vim.wait(200, function()
        local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        return text ~= '' and not text:match('Loading')
      end, 10)

      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('no LSP client', text)
    end)
  end)

  describe('keymaps', function()
    it('binds the configured keymaps as buffer-local normal-mode mappings', function()
      symbols.open()
      for _, lhs in ipairs({ '<CR>', 'q', '<Esc>', 'R' }) do
        local info = vim.fn.maparg(lhs, 'n', false, true)
        assert.are.equal(1, info.buffer, 'expected a buffer-local mapping for ' .. lhs)
      end
    end)

    it('<CR> jumps to the symbol under the cursor, in the buffer the outline was opened for', function()
      vim.cmd('enew')
      for _ = 1, 10 do
        vim.api.nvim_buf_set_lines(0, -1, -1, false, { '  some content here' })
      end
      local start_win = vim.api.nvim_get_current_win()
      local start_buf = vim.api.nvim_win_get_buf(start_win)

      respond_with({ { name = 'bar', kind = 6, range = range(5, 2, 5, 10) } })
      symbols.open()
      local outline_win = vim.api.nvim_get_current_win()
      assert.are_not.equal(start_win, outline_win)
      local buf = vim.api.nvim_win_get_buf(outline_win)

      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('bar') ~= nil
      end, 10)

      vim.api.nvim_win_set_cursor(outline_win, { 1, 0 })
      feed('<CR>')

      assert.are.equal(start_win, vim.api.nvim_get_current_win())
      assert.are.equal(start_buf, vim.api.nvim_win_get_buf(start_win))
      assert.are.same({ 6, 2 }, vim.api.nvim_win_get_cursor(start_win))
    end)

    it('<CR> on a message line (no symbol under cursor) does not error or move focus', function()
      vim.lsp.get_clients = function()
        return {}
      end
      symbols.open()
      local outline_win = vim.api.nvim_get_current_win()

      assert.has_no.errors(function()
        feed('<CR>')
      end)
      assert.are.equal(outline_win, vim.api.nvim_get_current_win())
    end)

    it('q closes the outline', function()
      symbols.open()
      local win = vim.api.nvim_get_current_win()
      feed('q')
      assert.is_false(symbols.is_open())
      assert.is_false(vim.api.nvim_win_is_valid(win))
    end)

    it('R re-requests symbols', function()
      respond_with({ { name = 'a', kind = 12, range = range(0, 0, 0, 1) } })
      symbols.open()
      local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('%[Function%] a') ~= nil
      end, 10)

      respond_with({ { name = 'b', kind = 13, range = range(0, 0, 0, 1) } })
      feed('R')
      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('%[Variable%] b') ~= nil
      end, 10)

      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('%[Variable%] b', text)
      assert.is_not.matches('%[Function%] a', text)
    end)
  end)

  describe('refresh', function()
    it('is a no-op before the outline has ever been opened', function()
      assert.has_no.errors(function()
        symbols.refresh()
      end)
    end)

    it('auto-refreshes on BufWritePost of the target buffer', function()
      vim.cmd('enew')
      local target_buf = vim.api.nvim_get_current_buf()

      respond_with({ { name = 'a', kind = 12, range = range(0, 0, 0, 1) } })
      symbols.open()
      local buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('a') ~= nil
      end, 10)

      respond_with({ { name = 'renamed', kind = 12, range = range(0, 0, 0, 1) } })
      vim.api.nvim_exec_autocmds('BufWritePost', { buffer = target_buf })

      vim.wait(200, function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):match('renamed') ~= nil
      end, 10)
      assert.matches('renamed', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    end)
  end)

  describe('setup', function()
    local orig_mapleader

    before_each(function()
      orig_mapleader = vim.g.mapleader
      vim.g.mapleader = ' '
    end)

    after_each(function()
      pcall(vim.keymap.del, 'n', '<leader>ll')
      pcall(vim.keymap.del, 'n', '<leader>o')
      vim.g.mapleader = orig_mapleader
    end)

    it('binds the trigger keymap to toggle the outline', function()
      symbols.setup({})
      assert.is_false(symbols.is_open())
      feed('<leader>ll')
      assert.is_true(symbols.is_open())
    end)

    it('honors a custom trigger keymap override', function()
      symbols.setup({ triggers = { toggle = { '<leader>o' } } })
      assert.is_false(symbols.is_open())
      feed('<leader>o')
      assert.is_true(symbols.is_open())
    end)
  end)
end)

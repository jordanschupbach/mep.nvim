local ft = require('mep.filetree.filetree')
local ft_config = require('mep.filetree.config')

local function mktemp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(content or '')
  f:close()
end

describe('mep.filetree.filetree', function()
  local saved_options
  local root

  before_each(function()
    saved_options = vim.deepcopy(ft_config.options)
    root = mktemp_dir()
    write_file(root .. '/a_file.txt', 'hello\n')
    vim.fn.mkdir(root .. '/a_dir', 'p')
    write_file(root .. '/a_dir/nested.txt', 'nested\n')
  end)

  after_each(function()
    ft.reset()
    ft_config.options = saved_options
    vim.fn.delete(root, 'rf')
  end)

  describe('open / close / toggle / is_open', function()
    it('is closed until opened', function()
      assert.is_false(ft.is_open())
    end)

    it('open() opens a window and renders the root', function()
      ft.open({ root = root })
      assert.is_true(ft.is_open())
    end)

    it('open() is a no-op if already open', function()
      ft.open({ root = root })
      local win_before = vim.api.nvim_get_current_win()
      ft.open({ root = root })
      assert.are.equal(win_before, vim.api.nvim_get_current_win())
    end)

    it('close() closes the window', function()
      ft.open({ root = root })
      ft.close()
      assert.is_false(ft.is_open())
    end)

    it('close() is a no-op if not open', function()
      assert.has_no.errors(function()
        ft.close()
      end)
    end)

    it('toggle() opens when closed and closes when open', function()
      ft.toggle({ root = root })
      assert.is_true(ft.is_open())
      ft.toggle({ root = root })
      assert.is_false(ft.is_open())
    end)
  end)

  describe('rendering', function()
    it('shows the root\'s immediate children after open', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      local text = table.concat(lines, '\n')
      assert.matches('a_dir/', text)
      assert.matches('a_file%.txt', text)
    end)
  end)

  describe('keymaps', function()
    it('binds the configured keymaps as buffer-local normal-mode mappings', function()
      ft.open({ root = root })

      for _, lhs in ipairs({ '<CR>', 'o', 'l', 'h', 'q', 'R' }) do
        local info = vim.fn.maparg(lhs, 'n', false, true)
        assert.are.equal(1, info.buffer, 'expected a buffer-local mapping for ' .. lhs)
      end
    end)
  end)

  describe('navigation', function()
    local function line_matching(buf, pattern)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:match(pattern) then
          return i
        end
      end
      error('no line matching ' .. pattern)
    end

    it('pressing open on a collapsed directory expands it in place', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local dir_line = line_matching(buf, 'a_dir/')
      vim.api.nvim_win_set_cursor(win, { dir_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)

      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('nested%.txt', text)
    end)

    it('pressing open on a file switches to the window the tree was opened from and opens it', function()
      vim.cmd('enew')
      local start_win = vim.api.nvim_get_current_win()

      ft.open({ root = root })
      local tree_win = vim.api.nvim_get_current_win()
      assert.are_not.equal(start_win, tree_win)

      local buf = vim.api.nvim_win_get_buf(tree_win)
      local file_line = line_matching(buf, 'a_file%.txt')
      vim.api.nvim_win_set_cursor(tree_win, { file_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)

      assert.are.equal(start_win, vim.api.nvim_get_current_win())
      assert.are.equal(root .. '/a_file.txt', vim.api.nvim_buf_get_name(0))
    end)

    it('collapse on an expanded directory collapses it without moving the cursor off it', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local dir_line = line_matching(buf, 'a_dir/')
      vim.api.nvim_win_set_cursor(win, { dir_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('l', true, false, true), 'x', false) -- expand
      assert.matches('nested%.txt', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))

      vim.api.nvim_win_set_cursor(win, { dir_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('h', true, false, true), 'x', false) -- collapse
      assert.is_not.matches('nested%.txt', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    end)

    it('collapse on a file moves the cursor to its parent directory\'s line', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local dir_line = line_matching(buf, 'a_dir/')
      vim.api.nvim_win_set_cursor(win, { dir_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('l', true, false, true), 'x', false) -- expand a_dir

      local nested_line = line_matching(buf, 'nested%.txt')
      vim.api.nvim_win_set_cursor(win, { nested_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('h', true, false, true), 'x', false)

      assert.are.equal(dir_line, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('close keymap closes the tree', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('q', true, false, true), 'x', false)
      assert.is_false(ft.is_open())
      assert.is_false(vim.api.nvim_win_is_valid(win))
    end)
  end)

  describe('refresh', function()
    it('picks up new files added on disk since the last render', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      write_file(root .. '/brand_new.txt', '')
      local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.is_not.matches('brand_new%.txt', before)

      ft.refresh()

      local after = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('brand_new%.txt', after)
    end)

    it('is a no-op before the tree has ever been opened', function()
      assert.has_no.errors(function()
        ft.refresh()
      end)
    end)
  end)

  describe('reset', function()
    it('closes the tree and forgets the cached root, so a later open rebuilds fresh', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- root line itself
      -- expand a_dir so there's cached state to forget
      local buf = vim.api.nvim_win_get_buf(win)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:match('a_dir/') then
          vim.api.nvim_win_set_cursor(win, { i, 0 })
        end
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('l', true, false, true), 'x', false)

      ft.reset()
      assert.is_false(ft.is_open())

      ft.open({ root = root })
      local reopened_buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      local text = table.concat(vim.api.nvim_buf_get_lines(reopened_buf, 0, -1, false), '\n')
      assert.is_not.matches('nested%.txt', text) -- a_dir is collapsed again
    end)
  end)
end)

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

      for _, lhs in ipairs({ '<CR>', 'o', 'l', 'h', 'q', 'R', 'H', 'a', 'r', 'd', '?', '<C-o>' }) do
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

  describe('open_system', function()
    local orig_ui_open

    before_each(function()
      orig_ui_open = vim.ui.open
    end)

    after_each(function()
      vim.ui.open = orig_ui_open
    end)

    local function line_matching(buf, pattern)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:match(pattern) then
          return i
        end
      end
      error('no line matching ' .. pattern)
    end

    it('opens the file under the cursor with vim.ui.open', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local opened
      vim.ui.open = function(path)
        opened = path
      end
      vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-o>', true, false, true), 'x', false)

      assert.are.equal(root .. '/a_file.txt', opened)
    end)

    it('opens a directory under the cursor too, unlike the normal open keymap', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local opened
      vim.ui.open = function(path)
        opened = path
      end
      vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_dir/'), 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-o>', true, false, true), 'x', false)

      assert.are.equal(root .. '/a_dir', opened)
    end)

    it('stays inside Neovim, never switching to the target window', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      vim.ui.open = function() end
      vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-o>', true, false, true), 'x', false)

      assert.are.equal(win, vim.api.nvim_get_current_win())
    end)

    it('warns instead of erroring when vim.ui.open is unavailable', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      vim.ui.open = nil
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })

      assert.has_no.errors(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-o>', true, false, true), 'x', false)
      end)

      vim.notify = orig_notify
      assert.is_true(warned)
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

  describe('toggle_hidden (H)', function()
    it('reveals dotfiles and gitignored files together, then hides them again', function()
      write_file(root .. '/.dotfile', '')
      vim.fn.system({ 'git', '-C', root, 'init', '-q' })
      write_file(root .. '/.gitignore', 'ignored.txt\n')
      write_file(root .. '/ignored.txt', '')

      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.is_not.matches('%.dotfile', before)
      assert.is_not.matches('ignored%.txt', before)

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('H', true, false, true), 'x', false)
      local shown = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.matches('%.dotfile', shown)
      assert.matches('ignored%.txt', shown)

      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('H', true, false, true), 'x', false)
      local hidden_again = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      assert.is_not.matches('%.dotfile', hidden_again)
      assert.is_not.matches('ignored%.txt', hidden_again)
    end)

    it('is a no-op before the tree has ever been opened', function()
      assert.has_no.errors(function()
        ft.toggle_hidden()
      end)
    end)
  end)

  describe('add / rename / delete', function()
    local orig_input, orig_confirm

    local function line_matching(buf, pattern)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:match(pattern) then
          return i
        end
      end
      error('no line matching ' .. pattern)
    end

    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    before_each(function()
      orig_input = vim.ui.input
      orig_confirm = vim.fn.confirm
    end)

    after_each(function()
      vim.ui.input = orig_input
      vim.fn.confirm = orig_confirm
    end)

    describe('add', function()
      it('creates a file inside the directory under the cursor and selects it', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.ui.input = function(_, on_confirm)
          on_confirm('new_file.txt')
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_dir/'), 0 })
        feed('a')

        assert.are.equal(1, vim.fn.filereadable(root .. '/a_dir/new_file.txt'))
        local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        assert.matches('new_file%.txt', text)
        assert.matches('new_file%.txt', vim.api.nvim_buf_get_lines(buf, 0, -1, false)[vim.api.nvim_win_get_cursor(win)[1]])
      end)

      it('creates a directory when the entered name ends with /', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.ui.input = function(_, on_confirm)
          on_confirm('new_dir/')
        end
        vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- root line
        feed('a')

        assert.are.equal(1, vim.fn.isdirectory(root .. '/new_dir'))
        assert.matches('new_dir/', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      end)

      it('creates a sibling file next to the file under the cursor, in its parent directory', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.ui.input = function(_, on_confirm)
          on_confirm('sibling.txt')
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
        feed('a')

        assert.are.equal(1, vim.fn.filereadable(root .. '/sibling.txt'))
      end)

      it('does not create anything when the prompt is cancelled', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()

        vim.ui.input = function(_, on_confirm)
          on_confirm(nil)
        end
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        feed('a')

        assert.are.equal(0, vim.fn.filereadable(root .. '/new_file.txt'))
      end)

      it('does not collapse an unrelated, already-expanded directory elsewhere in the tree', function()
        write_file(root .. '/b_dir/other.txt', '')
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'b_dir/'), 0 })
        feed('l') -- expand b_dir
        assert.matches('other%.txt', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))

        vim.ui.input = function(_, on_confirm)
          on_confirm('new_file.txt')
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_dir/'), 0 })
        feed('a')

        local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        assert.matches('other%.txt', text)
        assert.matches('new_file%.txt', text)
      end)

      it('refuses to overwrite an existing entry', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()

        local notified = false
        local orig_notify = vim.notify
        vim.notify = function(msg, level)
          if level == vim.log.levels.ERROR then
            notified = true
          end
        end
        vim.ui.input = function(_, on_confirm)
          on_confirm('a_file.txt')
        end
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        feed('a')
        vim.notify = orig_notify

        assert.is_true(notified)
        assert.are.equal('hello\n', table.concat(vim.fn.readfile(root .. '/a_file.txt'), '\n') .. '\n')
      end)
    end)

    describe('rename', function()
      it('renames the file under the cursor on disk and re-selects it', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.ui.input = function(_, on_confirm)
          on_confirm('renamed.txt')
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
        feed('r')

        assert.are.equal(0, vim.fn.filereadable(root .. '/a_file.txt'))
        assert.are.equal(1, vim.fn.filereadable(root .. '/renamed.txt'))
        assert.matches('renamed%.txt', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      end)

      it('refuses to rename the tree root', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()

        local called = false
        vim.ui.input = function()
          called = true
        end
        vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- root line
        feed('r')

        assert.is_false(called)
      end)

      it('refuses to rename onto an existing entry', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.ui.input = function(_, on_confirm)
          on_confirm('a_dir') -- collides with the existing directory
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
        feed('r')

        assert.are.equal(1, vim.fn.filereadable(root .. '/a_file.txt'))
      end)
    end)

    describe('delete', function()
      it('deletes the file under the cursor after confirming, and selects the parent', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.fn.confirm = function()
          return 1 -- "Yes"
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
        feed('d')

        assert.are.equal(0, vim.fn.filereadable(root .. '/a_file.txt'))
        assert.is_not.matches('a_file%.txt', table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      end)

      it('does nothing when the confirmation is declined', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.fn.confirm = function()
          return 2 -- "No"
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_file%.txt'), 0 })
        feed('d')

        assert.are.equal(1, vim.fn.filereadable(root .. '/a_file.txt'))
      end)

      it('recursively deletes a non-empty directory', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)

        vim.fn.confirm = function()
          return 1
        end
        vim.api.nvim_win_set_cursor(win, { line_matching(buf, 'a_dir/'), 0 })
        feed('d')

        assert.are.equal(0, vim.fn.isdirectory(root .. '/a_dir'))
      end)

      it('refuses to delete the tree root', function()
        ft.open({ root = root })
        local win = vim.api.nvim_get_current_win()

        local called = false
        vim.fn.confirm = function()
          called = true
          return 1
        end
        vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- root line
        feed('d')

        assert.is_false(called)
        assert.are.equal(1, vim.fn.isdirectory(root))
      end)
    end)
  end)

  describe('help', function()
    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
    end

    it('shows a horizontal rule and a "Press ? for help" hint below the tree', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('Press ? for help', lines[#lines])
      assert.are.equal('', (lines[#lines - 1]:gsub('─', ''))) -- the rule is made up of nothing but the rule char
    end)

    it('pins the hint to the very bottom of the window, not just after the last file', function()
      ft.open({ root = root })
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_win_get_buf(win)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- the tree only has a couple of entries, far fewer than the window
      -- is tall, so the buffer should be padded out to the window's full
      -- height rather than ending right after the last file.
      assert.are.equal(vim.api.nvim_win_get_height(win), #lines)
      -- root, a_dir/, a_file.txt: three tree lines, then blank padding
      -- until the footer's last two lines.
      assert.are.equal('', lines[4]) -- blank padding between the tree and the footer
    end)

    it('? opens a popup window listing every tree keymap', function()
      ft.open({ root = root })
      local tree_win = vim.api.nvim_get_current_win()

      feed('?')

      local help_win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if w ~= tree_win then
          help_win = w
        end
      end
      assert.is_not_nil(help_win)
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(help_win), 0, -1, false), '\n')
      assert.matches('Open file', text)
      assert.matches('Delete', text)
      assert.matches('Rename', text)
      assert.matches('Toggle this help', text)
    end)

    it('? again closes the popup', function()
      ft.open({ root = root })
      local win_count_before = #vim.api.nvim_list_wins()

      feed('?')
      assert.are.equal(win_count_before + 1, #vim.api.nvim_list_wins())

      feed('?')
      assert.are.equal(win_count_before, #vim.api.nvim_list_wins())
    end)

    it('q closes the popup without closing the tree', function()
      ft.open({ root = root })
      feed('?')
      local win_count_with_help = #vim.api.nvim_list_wins()

      feed('q')

      assert.are.equal(win_count_with_help - 1, #vim.api.nvim_list_wins())
      assert.is_true(ft.is_open())
    end)

    it('closing the tree also closes an open help popup', function()
      ft.open({ root = root })
      feed('?')
      local win_count_with_help = #vim.api.nvim_list_wins()
      assert.is_true(win_count_with_help > 1)

      ft.close()

      assert.are.equal(win_count_with_help - 2, #vim.api.nvim_list_wins()) -- tree window + help window
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

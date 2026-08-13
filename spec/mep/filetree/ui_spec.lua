local ui = require('mep.filetree.ui')

describe('mep.filetree.ui', function()
  describe('create_window / close_window', function()
    it('creates a scratch buffer in a real (non-floating) split of the given width', function()
      local buf, win = ui.create_window(25)

      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.are.equal('wipe', vim.bo[buf].bufhidden)
      assert.are.equal('mep-filetree', vim.bo[buf].filetype)
      assert.are.equal(25, vim.api.nvim_win_get_width(win))

      ui.close_window(win)
    end)

    it('sets window-local display options suited to a tree panel', function()
      local buf, win = ui.create_window(25)
      assert.is_false(vim.wo[win].number)
      assert.is_false(vim.wo[win].wrap)
      assert.is_true(vim.wo[win].cursorline)
      assert.are.equal('no', vim.wo[win].signcolumn)
      ui.close_window(win)
    end)

    it('sets winfixwidth, so its own width survives an unrelated split/close elsewhere', function()
      local _, win = ui.create_window(25)
      assert.is_true(vim.wo[win].winfixwidth)

      vim.cmd('vsplit') -- an unrelated split, in whatever the "rest" of the layout is
      assert.are.equal(25, vim.api.nvim_win_get_width(win))
      vim.cmd('close') -- and closing it again

      assert.are.equal(25, vim.api.nvim_win_get_width(win))
      ui.close_window(win)
    end)

    it('close_window invalidates the window and is safe to call twice', function()
      local _, win = ui.create_window(25)
      ui.close_window(win)
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.has_no.errors(function()
        ui.close_window(win)
      end)
    end)

    it('close_window(nil) does not error', function()
      assert.has_no.errors(function()
        ui.close_window(nil)
      end)
    end)
  end)

  describe('render', function()
    local buf, win

    before_each(function()
      buf, win = ui.create_window(30)
    end)

    after_each(function()
      ui.close_window(win)
    end)

    it('renders one line per node, indented by depth, with the icon and name', function()
      local nodes = {
        { name = 'src', is_dir = true, expanded = true, depth = 0 },
        { name = 'main.lua', is_dir = false, depth = 1 },
      }
      ui.render(buf, nodes)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.matches('src/', lines[1])
      assert.matches('main%.lua', lines[2])
      -- the file line is indented one level deeper than the dir line
      assert.is_true(#(lines[2]:match('^%s*')) > #(lines[1]:match('^%s*')))
    end)

    it('shows the closed-vs-open expand marker based on node.expanded', function()
      local closed = { { name = 'a', is_dir = true, expanded = false, depth = 0 } }
      ui.render(buf, closed)
      local closed_line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]

      local open = { { name = 'a', is_dir = true, expanded = true, depth = 0 } }
      ui.render(buf, open)
      local open_line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]

      assert.are_not.equal(closed_line, open_line)
    end)

    it('highlights the icon on every line', function()
      local nodes = {
        { name = 'src', is_dir = true, expanded = true, depth = 0 },
        { name = 'main.lua', is_dir = false, depth = 1 },
      }
      ui.render(buf, nodes)

      local ns = vim.api.nvim_get_namespaces()['mep_filetree_icons']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(2, #marks)
    end)

    it('highlights directory names but not file names', function()
      local nodes = {
        { name = 'src', is_dir = true, expanded = true, depth = 0 },
        { name = 'main.lua', is_dir = false, depth = 1 },
      }
      ui.render(buf, nodes)

      local ns = vim.api.nvim_get_namespaces()['mep_filetree_names']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
      assert.are.equal(0, marks[1][2]) -- row 0: the directory line
    end)

    it('leaves the buffer unmodifiable after rendering', function()
      ui.render(buf, {})
      assert.is_false(vim.bo[buf].modifiable)
    end)

    it('clears previous highlights when re-rendering with fewer nodes', function()
      ui.render(buf, {
        { name = 'a', is_dir = true, expanded = true, depth = 0 },
        { name = 'b', is_dir = true, expanded = true, depth = 0 },
      })
      ui.render(buf, { { name = 'a', is_dir = false, depth = 0 } })

      local ns = vim.api.nvim_get_namespaces()['mep_filetree_names']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(0, #marks) -- the single remaining node is a file, not a dir
    end)
  end)
end)

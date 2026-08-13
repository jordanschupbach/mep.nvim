local ui = require('mep.dashboard.ui')

describe('mep.dashboard.ui', function()
  describe('prepare_buffer', function()
    it('configures a non-editable, unlisted scratch buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      ui.prepare_buffer(buf)
      assert.are.equal('nofile', vim.bo[buf].buftype)
      assert.are.equal('wipe', vim.bo[buf].bufhidden)
      assert.is_false(vim.bo[buf].swapfile)
      assert.is_false(vim.bo[buf].buflisted)
      assert.are.equal('mep-dashboard', vim.bo[buf].filetype)
    end)
  end)

  describe('prepare_window / restore_window', function()
    local win

    before_each(function()
      local buf = vim.api.nvim_create_buf(false, true)
      win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
    end)

    after_each(function()
      pcall(vim.api.nvim_win_close, win, true)
    end)

    it('turns off number, relativenumber, and the sign column', function()
      ui.prepare_window(win)
      assert.is_false(vim.wo[win].number)
      assert.is_false(vim.wo[win].relativenumber)
      assert.are.equal('no', vim.wo[win].signcolumn)
    end)

    it('blanks the end-of-buffer ~ filler', function()
      ui.prepare_window(win)
      assert.matches('eob: ', vim.wo[win].fillchars)
    end)

    it('restore_window puts the previous values back', function()
      vim.wo[win].number = true
      vim.wo[win].signcolumn = 'yes'
      local saved = ui.prepare_window(win)
      assert.is_false(vim.wo[win].number)

      ui.restore_window(win, saved)
      assert.is_true(vim.wo[win].number)
      assert.are.equal('yes', vim.wo[win].signcolumn)
    end)

    it('restore_window is a no-op on an already-closed window', function()
      local saved = ui.prepare_window(win)
      vim.api.nvim_win_close(win, true)
      assert.has_no.errors(function()
        ui.restore_window(win, saved)
      end)
    end)
  end)

  describe('center', function()
    it('pads each line to horizontally center it within the given width', function()
      local out = ui.center({ 'ab' }, 10, 1)
      -- (10 - 2) / 2 = 4 leading spaces
      assert.are.equal('    ab', out[1])
    end)

    it('does not pad a line already as wide as (or wider than) the window', function()
      local out = ui.center({ 'abcdefghij' }, 10, 1)
      assert.are.equal('abcdefghij', out[1])
    end)

    it('pads blank lines above the block to vertically center it', function()
      local out = ui.center({ 'a', 'b' }, 10, 6)
      -- (6 - 2) / 2 = 2 blank lines above
      assert.are.same({ '', '', '    a', '    b' }, out)
    end)

    it('adds no vertical padding when the content already fills the height', function()
      local out = ui.center({ 'a', 'b', 'c' }, 10, 2)
      assert.are.equal(3, #out) -- no negative/extra padding
    end)

    it('handles an empty line list (still vertically pads to center "nothing")', function()
      assert.are.same({ '', '' }, ui.center({}, 10, 4))
    end)
  end)

  describe('render', function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
    end)

    it('writes the given lines into the buffer', function()
      ui.render(buf, { 'one', 'two' })
      assert.are.same({ 'one', 'two' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('leaves the buffer unmodifiable afterward', function()
      ui.render(buf, { 'x' })
      assert.is_false(vim.bo[buf].modifiable)
    end)

    describe('highlighting', function()
      local ns

      before_each(function()
        ns = vim.api.nvim_get_namespaces()['mep_dashboard']
      end)

      local function marks_for(lines)
        ui.render(buf, lines)
        return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      end

      it('highlights a block-character logo line as MepDashboardLogo', function()
        local marks = marks_for({ '██  ██' })
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardLogo', marks[1][4].hl_group)
        assert.are.equal(0, marks[1][3])
      end)

      it('does not treat a version line as a logo line', function()
        local marks = marks_for({ 'NVIM v0.11.7' })
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardVersion', marks[1][4].hl_group)
      end)

      it('highlights every row of the real dashboard logo', function()
        local content = require('mep.dashboard.content')
        local marks = marks_for(content.LOGO)
        assert.are.equal(#content.LOGO, #marks)
        for _, m in ipairs(marks) do
          assert.are.equal('MepDashboardLogo', m[4].hl_group)
        end
      end)

      it('highlights a whole "PRODUCT vX.Y.Z" line as MepDashboardVersion', function()
        local marks = marks_for({ 'NVIM v0.11.7' })
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardVersion', marks[1][4].hl_group)
        assert.are.equal(0, marks[1][3])
        assert.are.equal(12, marks[1][4].end_col) -- the whole line
      end)

      it('still recognizes a version line after centering padding is added', function()
        local marks = marks_for(ui.center({ 'MEP v0.0.1' }, 40, 1))
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardVersion', marks[1][4].hl_group)
      end)

      it('underlines just the URL portion of a line as MepDashboardLink', function()
        local marks = marks_for({ 'see https://neovim.io/#chat for chat' })
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardLink', marks[1][4].hl_group)
        local line = 'see https://neovim.io/#chat for chat'
        assert.are.equal('https://neovim.io/#chat', line:sub(marks[1][3] + 1, marks[1][4].end_col))
      end)

      it('highlights a :command<Enter> hint as MepDashboardCommand', function()
        local line = 'type  :help nvim<Enter>       if you are new!'
        local marks = marks_for({ line })
        assert.are.equal(1, #marks)
        assert.are.equal('MepDashboardCommand', marks[1][4].hl_group)
        assert.are.equal(':help nvim<Enter>', line:sub(marks[1][3] + 1, marks[1][4].end_col))
      end)

      it('highlights both a URL and a command hint when a line has both', function()
        local marks = marks_for({ 'https://x.example type :q<Enter> to quit' })
        assert.are.equal(2, #marks)
      end)

      it('leaves plain text and blank lines unhighlighted', function()
        local marks = marks_for({ 'Nvim is open source and freely distributable', '' })
        assert.are.same({}, marks)
      end)
    end)

    it('is a no-op on an invalid buffer', function()
      local invalid = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(invalid, { force = true })
      assert.has_no.errors(function()
        ui.render(invalid, { 'x' })
      end)
    end)
  end)
end)

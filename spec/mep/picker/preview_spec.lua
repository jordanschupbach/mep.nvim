local preview = require('mep.picker.preview')

local function mktemp_file(content)
  local path = vim.fn.tempname() .. '.lua'
  local f = assert(io.open(path, 'w'))
  f:write(content)
  f:close()
  return path
end

local function make_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = 20,
    height = 5,
    style = 'minimal',
  })
  return buf, win
end

describe('mep.picker.preview', function()
  local buf, win

  before_each(function()
    buf, win = make_win()
  end)

  after_each(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)

  describe('show_file', function()
    it('loads file content, detects filetype, and centers the target line', function()
      local path = mktemp_file('local a = 1\nlocal b = 2\nlocal c = 3\n')

      preview.show_file(buf, win, path, 2)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ 'local a = 1', 'local b = 2', 'local c = 3' }, lines)
      assert.are.equal('lua', vim.bo[buf].filetype)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      assert.is_false(vim.bo[buf].modifiable)

      os.remove(path)
    end)

    it('clamps a line number beyond the end of the file', function()
      local path = mktemp_file('one\ntwo\n')
      preview.show_file(buf, win, path, 999)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      os.remove(path)
    end)

    it('shows a placeholder instead of erroring for a missing file', function()
      assert.has_no.errors(function()
        preview.show_file(buf, win, '/no/such/file/anywhere.lua', 1)
      end)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.matches('unable to preview', lines[1])
    end)

    it('highlights the target line with a MepPreviewLine extmark', function()
      local path = mktemp_file('a\nb\nc\n')
      preview.show_file(buf, win, path, 2)

      local ns = vim.api.nvim_get_namespaces()['mep_picker_preview_line']
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
      assert.are.equal(1, #marks)
      assert.are.equal(1, marks[1][2]) -- 0-based row for line 2

      os.remove(path)
    end)
  end)

  describe('show_buffer', function()
    it('copies the live contents and filetype of a source buffer', function()
      local src = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(src, 0, -1, false, { 'x = 1', 'y = 2' })
      vim.bo[src].filetype = 'python'

      preview.show_buffer(buf, win, src, 2)

      assert.are.same({ 'x = 1', 'y = 2' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.equal('python', vim.bo[buf].filetype)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it('disables folding so a source filetype with fold-by-default content is fully visible', function()
      -- Reproduces the bug where previewing an org buffer (whose FileType
      -- autocmd turns on an expr foldmethod that starts closed) left the
      -- preview showing only the outermost folded headline text instead
      -- of the buffer's actual lines.
      local src = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(src, 0, -1, false, { '* Heading', 'body line 1', 'body line 2' })
      vim.bo[src].filetype = 'org'

      vim.wo[win].foldmethod = 'manual'
      vim.api.nvim_win_call(win, function()
        vim.cmd('normal! zf2j')
      end)
      assert.is_true(vim.wo[win].foldenable)

      preview.show_buffer(buf, win, src, 1)

      assert.is_false(vim.wo[win].foldenable)
    end)
  end)

  describe('clear', function()
    it('blanks the buffer and its filetype', function()
      local path = mktemp_file('content\n')
      preview.show_file(buf, win, path, 1)

      preview.clear(buf)

      assert.are.same({ '' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.are.equal('', vim.bo[buf].filetype)

      os.remove(path)
    end)
  end)
end)

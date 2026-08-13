local buffer_lines = require('mep.picker.sources.buffer_lines')

local function make_win(buf)
  return vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = 20,
    height = 5,
    style = 'minimal',
  })
end

describe('mep.picker.sources.buffer_lines', function()
  local buf, win

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      'local function hello()',
      '',
      '  print("hi")',
      '   ', -- whitespace-only, should also be excluded
      'end',
    })
    win = make_win(buf)
  end)

  after_each(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)

  it('indexes only non-blank lines, keeping their original line numbers', function()
    local opts = buffer_lines.picker_opts({ bufnr = buf, winid = win })
    assert.are.equal(3, #opts.items)
    assert.are.same({ 1, 3, 5 }, { opts.items[1].lnum, opts.items[2].lnum, opts.items[3].lnum })
  end)

  it('formats display as a right-aligned line number plus the line text', function()
    local opts = buffer_lines.picker_opts({ bufnr = buf, winid = win })
    assert.are.equal('   1: local function hello()', opts.items[1].display)
    assert.are.equal(opts.items[1].display, opts.entry_to_string(opts.items[1]))
  end)

  it('names the prompt title after the buffer\'s file name', function()
    vim.api.nvim_buf_set_name(buf, '/some/path/example.lua')
    local opts = buffer_lines.picker_opts({ bufnr = buf, winid = win })
    assert.matches('example%.lua', opts.prompt_title)
  end)

  it('defaults bufnr/winid to the current buffer and window', function()
    vim.api.nvim_set_current_win(win)
    local opts = buffer_lines.picker_opts({})
    assert.are.equal(3, #opts.items)
  end)

  it('preview() delegates to preview.show_buffer with the source bufnr and item lnum', function()
    local preview_mod = require('mep.picker.preview')
    local orig = preview_mod.show_buffer
    local captured
    preview_mod.show_buffer = function(pbuf, pwin, src_bufnr, lnum)
      captured = { pbuf = pbuf, pwin = pwin, src_bufnr = src_bufnr, lnum = lnum }
    end

    local opts = buffer_lines.picker_opts({ bufnr = buf, winid = win })
    local preview_buf = vim.api.nvim_create_buf(false, true)
    opts.preview(opts.items[2], preview_buf, win)

    preview_mod.show_buffer = orig

    assert.are.equal(preview_buf, captured.pbuf)
    assert.are.equal(buf, captured.src_bufnr)
    assert.are.equal(3, captured.lnum)
  end)

  it('on_select() jumps the source window to the item\'s line', function()
    local opts = buffer_lines.picker_opts({ bufnr = buf, winid = win })
    opts.on_select(opts.items[3]) -- lnum 5, the 'end' line

    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal(5, vim.api.nvim_win_get_cursor(win)[1])
  end)
end)

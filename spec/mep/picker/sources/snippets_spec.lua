local snippets_source = require('mep.picker.sources.snippets')
local registry = require('mep.snippet.registry')
local session = require('mep.snippet.session')

local function make_buf_win(filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = filetype
  local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
  return buf, win
end

describe('mep.picker.sources.snippets', function()
  after_each(function()
    registry._reset()
    session._reset()
  end)

  it('lists every snippet registered for the buffer\'s own filetype', function()
    registry.add('lua', { { trigger = 'fun', body = 'function $1()\n\t$0\nend' } })
    local buf, win = make_buf_win('lua')

    local opts = snippets_source.picker_opts({ bufnr = buf, win = win })
    assert.are.equal(1, #opts.items)
    assert.are.equal('fun', opts.items[1].trigger)

    vim.api.nvim_win_close(win, true)
  end)

  it('is scoped to the filetype, excluding other filetypes\' snippets', function()
    registry.add('lua', { { trigger = 'fun', body = 'F' } })
    registry.add('python', { { trigger = 'def', body = 'D' } })
    local buf, win = make_buf_win('lua')

    local opts = snippets_source.picker_opts({ bufnr = buf, win = win })
    assert.are.equal(1, #opts.items)
    assert.are.equal('fun', opts.items[1].trigger)

    vim.api.nvim_win_close(win, true)
  end)

  it('entry_to_string shows the trigger and the first line of the body', function()
    registry.add('lua', { { trigger = 'fun', body = 'function $1()\n\t$0\nend' } })
    local buf, win = make_buf_win('lua')

    local opts = snippets_source.picker_opts({ bufnr = buf, win = win })
    assert.are.equal('fun  function $1()', opts.entry_to_string(opts.items[1]))

    vim.api.nvim_win_close(win, true)
  end)

  it('on_select inserts the raw body at the cursor (not a trigger-word replace)', function()
    registry.add('lua', { { trigger = 'fun', body = 'F$1' } })
    local buf, win = make_buf_win('lua')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'xx' })
    -- Normal-mode cursor placement clamps to the last character (index
    -- 1 of a 2-char line), not one-past-the-end — insert mode has to be
    -- active for column 2 (true end-of-line) to stick, same as `mep.
    -- snippet`'s own spec's `set_cursor_after` helper.
    vim.api.nvim_set_current_win(win)
    vim.cmd('startinsert')
    vim.api.nvim_win_set_cursor(win, { 1, 2 })
    vim.cmd('stopinsert')

    local opts = snippets_source.picker_opts({ bufnr = buf, win = win })
    opts.on_select(opts.items[1])

    assert.are.same({ 'xxF' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    vim.api.nvim_win_close(win, true)
  end)

  it('includes the filetype in the prompt title', function()
    local buf, win = make_buf_win('lua')
    local opts = snippets_source.picker_opts({ bufnr = buf, win = win })
    assert.matches('lua', opts.prompt_title)
    vim.api.nvim_win_close(win, true)
  end)
end)

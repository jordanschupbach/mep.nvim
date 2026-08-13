-- Uses the real vim.treesitter API against the 'lua' parser, which ships
-- bundled with Neovim (see :h treesitter-parsers) — no subprocess or
-- mocking involved, unlike install_spec.lua.
local activate = require('mep.treesitter.activate')

local function make_buf(filetype, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { 'local x = 1' })
  vim.bo[buf].filetype = filetype
  return buf
end

describe('mep.treesitter.activate', function()
  after_each(function()
    -- highlighter state persists on the (wiped) buffer's bufnr slot
    -- otherwise, and bufnrs get reused across tests in the same process
    for bufnr in pairs(vim.treesitter.highlighter.active) do
      pcall(vim.treesitter.stop, bufnr)
    end
  end)

  it('returns nil for an empty filetype', function()
    local buf = make_buf('')
    assert.is_nil(activate.enable_for_buffer(buf))
  end)

  it('returns nil when no parser is available for the filetype', function()
    local buf = make_buf('mep-nonexistent-filetype-xyz')
    assert.is_nil(activate.enable_for_buffer(buf))
    assert.is_nil(vim.treesitter.highlighter.active[buf])
  end)

  it('returns the resolved language and starts highlighting by default', function()
    local buf = make_buf('lua')
    local lang = activate.enable_for_buffer(buf)
    assert.are.equal('lua', lang)
    assert.is_not_nil(vim.treesitter.highlighter.active[buf])
  end)

  it('resolves help filetype to the vimdoc parser (via the built-in language.get_lang mapping)', function()
    local buf = make_buf('help', { '*tag*' })
    local lang = activate.enable_for_buffer(buf)
    assert.are.equal('vimdoc', lang)
  end)

  it('does not start highlighting when opts.highlight is false', function()
    local buf = make_buf('lua')
    local lang = activate.enable_for_buffer(buf, { highlight = false })
    assert.are.equal('lua', lang) -- parser is still resolved/loaded
    assert.is_nil(vim.treesitter.highlighter.active[buf])
  end)

  it('sets foldmethod/foldexpr on windows showing the buffer when opts.fold is true', function()
    local buf = make_buf('lua')
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 10,
      height = 5,
      style = 'minimal',
    })

    activate.enable_for_buffer(buf, { fold = true })

    assert.are.equal('expr', vim.wo[win].foldmethod)
    assert.are.equal('v:lua.vim.treesitter.foldexpr()', vim.wo[win].foldexpr)

    vim.api.nvim_win_close(win, true)
  end)

  it('does not touch foldmethod when opts.fold is false/omitted', function()
    local buf = make_buf('lua')
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 10,
      height = 5,
      style = 'minimal',
    })
    local before = vim.wo[win].foldmethod

    activate.enable_for_buffer(buf, {})

    assert.are.equal(before, vim.wo[win].foldmethod)
    vim.api.nvim_win_close(win, true)
  end)
end)

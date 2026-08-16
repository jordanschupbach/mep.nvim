-- Real floating windows/buffers/autocmds work fine under nlua (see
-- spec/README.md) — only real subprocesses don't — so this drives the
-- popup through its own buffer-local keymap callbacks directly (found
-- via nvim_buf_get_keymap, the same "invoke the callback, not real
-- keystrokes" approach other keymap-driven specs in this suite use)
-- rather than simulating real input.
local popup = require('mep.ai.popup')

local function callback_for(buf, mode, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if map.lhs == lhs or map.lhs == vim.keycode(lhs) then
      return map.callback
    end
  end
  error('no ' .. mode .. '-mode mapping for ' .. lhs .. ' found on buffer ' .. buf)
end

describe('mep.ai.popup', function()
  local function open_popup(on_confirm)
    local before = vim.api.nvim_list_bufs()
    popup.prompt('mep.ai: instructions', on_confirm or function() end)
    local after = vim.api.nvim_list_bufs()
    local buf
    for _, b in ipairs(after) do
      if not vim.tbl_contains(before, b) then
        buf = b
      end
    end
    assert(buf, 'popup did not create a new buffer')
    return buf
  end

  it('opens a floating window over a fresh scratch, wiped-on-close scratch buffer', function()
    -- Not asserting the post-`:startinsert` mode here: nlua has no real
    -- UI/mode loop attached (see spec/README.md's own "not a full
    -- running editor" caveat, same underlying limitation, just a
    -- different symptom of it), so `vim.fn.mode()` doesn't reliably
    -- reflect it under this harness even though `:startinsert` runs for
    -- real in an actual editor session.
    local buf = open_popup()
    assert.are.equal('nofile', vim.bo[buf].buftype)
    assert.are.equal('wipe', vim.bo[buf].bufhidden)
    -- clean up: cancel via the buffer's own <Esc> mapping
    callback_for(buf, 'i', '<Esc>')()
  end)

  it('confirms with the typed text and closes the window on <CR>', function()
    local confirmed
    local buf = open_popup(function(text)
      confirmed = text
    end)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'fix the off-by-one error' })
    callback_for(buf, 'i', '<CR>')()

    assert.are.equal('fix the off-by-one error', confirmed)
    assert.is_false(vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1)
  end)

  it('does not call on_confirm on <Esc>', function()
    local called = false
    local buf = open_popup(function()
      called = true
    end)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'some text' })
    callback_for(buf, 'i', '<Esc>')()
    assert.is_false(called)
  end)

  it('does not call on_confirm for an empty confirmed line', function()
    local called = false
    local buf = open_popup(function()
      called = true
    end)
    -- buffer starts empty; confirm without typing anything
    callback_for(buf, 'i', '<CR>')()
    assert.is_false(called)
  end)

  it('is idempotent: <CR> then a leftover BufLeave/<Esc> does not double-fire or error', function()
    local calls = 0
    local buf = open_popup(function()
      calls = calls + 1
    end)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'once' })
    local cr = callback_for(buf, 'i', '<CR>')
    local esc = callback_for(buf, 'i', '<Esc>')
    cr()
    assert.has_no.errors(function()
      esc()
    end)
    assert.are.equal(1, calls)
  end)

  it('works from normal mode too (n-mode <CR>/<Esc> mappings)', function()
    local confirmed
    local buf = open_popup(function(text)
      confirmed = text
    end)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'refactor this' })
    callback_for(buf, 'n', '<CR>')()
    assert.are.equal('refactor this', confirmed)
  end)
end)

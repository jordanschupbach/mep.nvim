--- Aggregator for mep's snippet library: a full tabstop/placeholder
--- expansion engine (`mep.snippet.session`, `$1`/`${1:default}`/`$0`
--- syntax via `mep.snippet.parse`) over snippets registered per
--- filetype in plain Lua (`mep.snippet.registry`, no textmate/VSCode
--- JSON format) — `<Tab>` expands the trigger word before the cursor
--- (even outside `mep.completion`'s own popup) or jumps to the next
--- tabstop if a session is already active, `<S-Tab>` jumps backward.
---
--- `mep.completion.sources.snippet` and the snippet-shaped-`insertText`
--- fix in `mep.completion.sources.lsp` both call `M.expand` directly
--- (bypassing trigger lookup) once a completion item carrying a
--- snippet body has been accepted — see `mep.completion.engine`'s own
--- `CompleteDone` handling for how that's wired up.
local config = require('mep.snippet.config')
local registry = require('mep.snippet.registry')
local session = require('mep.snippet.session')
local parse = require('mep.snippet.parse')

local M = {}
M.registry = registry
M.session = session
M.parse = parse

--- Register `list` (each `{ trigger, body }`) as snippets for
--- `filetype` — see `mep.snippet.registry.add`.
function M.add(filetype, list)
  registry.add(filetype, list)
end

--- The keyword-character run (`[%w_]`, the same boundary `mep.
--- completion.engine`'s own prefix detection uses) immediately before
--- `win`'s cursor in `bufnr`.
local function word_before_cursor(bufnr, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  return line:sub(1, col):match('[%w_]*$') or ''
end

--- Try to expand the trigger word immediately before the cursor in
--- `bufnr`/`win` (defaulting to the current buffer/window), looked up
--- under its own `filetype`. Returns `true` if it did.
function M.expand_at_cursor(bufnr, win)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()
  local word = word_before_cursor(bufnr, win)
  if word == '' then
    return false
  end
  local filetype = vim.bo[bufnr].filetype
  local snip = registry.find(filetype, word)
  if not snip then
    return false
  end
  session.expand(bufnr, win, #word, snip.body)
  return true
end

--- Directly expand `body` at `bufnr`/`win`'s cursor, replacing
--- `replace_len` bytes immediately before it — bypasses trigger lookup,
--- for callers (the completion sources — see this module's own header
--- comment) that already have the exact body text in hand.
function M.expand(bufnr, win, replace_len, body)
  session.expand(bufnr, win, replace_len, body)
end

local FEED_TAB = vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
local FEED_S_TAB = vim.api.nvim_replace_termcodes('<S-Tab>', true, false, true)

local function on_tab()
  if session.is_active() then
    session.jump(1)
    return
  end
  if M.expand_at_cursor() then
    return
  end
  vim.api.nvim_feedkeys(FEED_TAB, 'n', false)
end

local function on_shift_tab()
  if session.is_active() then
    session.jump(-1)
    return
  end
  vim.api.nvim_feedkeys(FEED_S_TAB, 'n', false)
end

--- Configure mep.snippet: `tab_keymap` (see mep.snippet.config.
--- defaults). Works with sensible defaults even if this is never
--- called — only the `<Tab>`/`<S-Tab>` keymaps themselves need setup().
function M.setup(opts)
  local options = config.setup(opts)
  if options.tab_keymap then
    vim.keymap.set('i', '<Tab>', on_tab, { desc = 'mep.snippet: expand trigger / jump to next tabstop' })
    vim.keymap.set('i', '<S-Tab>', on_shift_tab, { desc = 'mep.snippet: jump to previous tabstop' })
  end
  return options
end

return M

--- Aggregator for mep's REPL library: one REPL kept alive per filetype
--- (or per buffer, `config.options.scope = 'buffer'`) in a real
--- `:terminal` split (`mep.project`'s own terminal-split usage as
--- precedent, and the same "no shell involved" `vim.fn.jobstart(cmd, {
--- term = true })` idiom `mep.run.terminal` uses), `send_line`/
--- `send_selection`/`send_buffer` writing to it via `vim.fn.chansend`.
---
--- Starting a REPL as a side effect of a `send_*` call (the first send
--- for a given scope key, before any session exists yet) briefly
--- splits/focuses the new terminal window, then returns focus to
--- wherever it was — sending a line of code shouldn't strand you in the
--- REPL window just because it happened to be the call that started it.
--- `M.jump_to_repl` is the one that's actually supposed to focus it;
--- `M.jump_back` is meant to be bound *inside* the REPL terminal buffer
--- itself (not globally — there's no single "current code buffer" to
--- jump back to from just anywhere), and looks up which session (if
--- any) the buffer it's called from belongs to.
local config = require('mep.repl.config')
local registry = require('mep.repl.registry')
local state = require('mep.repl.state')

local M = {}
M.registry = registry
M.state = state

local function session_key(bufnr)
  if config.options.scope == 'buffer' then
    return bufnr
  end
  return vim.bo[bufnr].filetype
end
M.session_key = session_key

local function command_for(filetype)
  return config.options.commands[filetype] or registry.commands[filetype]
end

--- Whether `session`'s own terminal job is still running — checked via
--- `jobwait` (0ms, non-blocking) rather than `buftype == 'terminal'`,
--- since a buffer's `buftype` stays `'terminal'` even after its job has
--- already exited.
local function session_alive(session)
  if not session or not vim.api.nvim_buf_is_valid(session.bufnr) then
    return false
  end
  local ok, result = pcall(vim.fn.jobwait, { session.job_id }, 0)
  return ok and result[1] == -1
end
M.session_alive = session_alive

--- Split below `source_win` (sized to `config.options.
--- terminal_height_ratio` of its own height) and run `cmd` there as a
--- real terminal job — `mep.run.terminal.open`'s own split/resize
--- logic, duplicated in this smaller form since it additionally needs
--- to return to (and later re-split from) a specific *source* window
--- rather than always "whatever's current".
local function open_terminal_for(cmd, source_win)
  local total_height = vim.api.nvim_win_get_height(source_win)
  vim.api.nvim_set_current_win(source_win)
  local save_splitbelow, save_equalalways = vim.o.splitbelow, vim.o.equalalways
  vim.o.splitbelow = true
  vim.o.equalalways = false
  vim.cmd('split')
  vim.o.splitbelow, vim.o.equalalways = save_splitbelow, save_equalalways

  local terminal_height = math.max(1, math.floor(total_height * config.options.terminal_height_ratio + 0.5))
  vim.cmd('resize ' .. terminal_height)

  vim.cmd('enew')
  local job_id = vim.fn.jobstart(cmd, { term = true })
  return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), job_id
end

--- Ensure a live REPL session exists for `bufnr`'s own scope key,
--- starting one if needed. Returns the session, or nil (with a
--- notification) if the filetype has no curated/configured launch
--- command.
local function ensure_session(bufnr)
  local key = session_key(bufnr)
  local existing = state.get(key)
  if session_alive(existing) then
    return existing
  end

  local filetype = vim.bo[bufnr].filetype
  local cmd = command_for(filetype)
  if not cmd then
    vim.notify('mep.repl: no REPL command for filetype "' .. filetype .. '"', vim.log.levels.WARN)
    return nil
  end

  local source_win = vim.api.nvim_get_current_win()
  local term_bufnr, term_win, job_id = open_terminal_for(cmd, source_win)
  local session = { bufnr = term_bufnr, win = term_win, job_id = job_id, source_win = source_win }
  state.set(key, session)

  -- Buffer-local to *this* REPL's own terminal buffer, bound right here
  -- rather than via a global `TermOpen` autocmd — `TermOpen` fires for
  -- any terminal in the editor, mep.repl's own or not, and there's no
  -- reason to bind a "jump back to the code that started this" keymap
  -- inside an unrelated one.
  for _, lhs in ipairs(config.options.keymaps.jump_back) do
    vim.keymap.set('n', lhs, M.jump_back, { buffer = term_bufnr, desc = 'mep.repl: jump back to the code window' })
  end

  if vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end
  return session
end
M.ensure_session = ensure_session

--- Send `text` (embedded newlines send as separate REPL submissions —
--- a trailing newline is appended so the REPL actually evaluates it) to
--- `bufnr`'s own REPL session, opening one first if none is alive yet.
local function send(bufnr, text)
  local session = ensure_session(bufnr)
  if not session then
    return
  end
  vim.fn.chansend(session.job_id, text .. '\n')
end

--- Send the line at `lnum` (default the cursor's own line, in the
--- current window) in `bufnr`.
function M.send_line(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  send(bufnr, line)
end

--- Send every line from `start_line` to `end_line` (1-based, inclusive)
--- in `bufnr`.
function M.send_selection(bufnr, start_line, end_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  send(bufnr, table.concat(lines, '\n'))
end

--- Send `bufnr`'s own full contents.
function M.send_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  send(bufnr, table.concat(lines, '\n'))
end

--- Jump to (starting first if needed) the REPL window for `bufnr`'s own
--- scope key — reopens a split showing the same terminal buffer if the
--- session's alive but its window was closed, rather than starting a
--- second job for the same key.
function M.jump_to_repl(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = ensure_session(bufnr)
  if not session then
    return
  end
  if session.win and vim.api.nvim_win_is_valid(session.win) then
    vim.api.nvim_set_current_win(session.win)
    return
  end
  local save_splitbelow, save_equalalways = vim.o.splitbelow, vim.o.equalalways
  vim.o.splitbelow = true
  vim.o.equalalways = false
  vim.cmd('split')
  vim.o.splitbelow, vim.o.equalalways = save_splitbelow, save_equalalways
  vim.api.nvim_win_set_buf(0, session.bufnr)
  session.win = vim.api.nvim_get_current_win()
end

--- Jump back to whichever window the REPL session *the current buffer
--- belongs to* was originally opened from — meant to be called from
--- inside a REPL terminal buffer itself (see this module's own header
--- comment); a no-op if the current buffer isn't a tracked REPL
--- session, or its source window has since closed.
function M.jump_back()
  local cur = vim.api.nvim_get_current_buf()
  for _, session in pairs(state.all()) do
    if session.bufnr == cur then
      if session.source_win and vim.api.nvim_win_is_valid(session.source_win) then
        vim.api.nvim_set_current_win(session.source_win)
      end
      return
    end
  end
end

--- Configure mep.repl: `scope`, extra/override `commands`,
--- `terminal_height_ratio`, and `keymaps` (see mep.repl.config.
--- defaults — `send_selection` binds in visual mode only,
--- `jump_back` binds inside every REPL terminal buffer this library
--- creates, the rest bind globally in normal mode). Works with sensible
--- defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  local km = options.keymaps

  for _, lhs in ipairs(km.send_line) do
    vim.keymap.set('n', lhs, function()
      M.send_line()
    end, { desc = 'mep.repl: send the current line' })
  end
  for _, lhs in ipairs(km.send_selection) do
    vim.keymap.set('x', lhs, function()
      local start_line, end_line = vim.fn.line('v'), vim.fn.line('.')
      vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes('<Esc>', true, false, true))
      M.send_selection(vim.api.nvim_get_current_buf(), start_line, end_line)
    end, { desc = 'mep.repl: send the visual selection' })
  end
  for _, lhs in ipairs(km.send_buffer) do
    vim.keymap.set('n', lhs, function()
      M.send_buffer()
    end, { desc = 'mep.repl: send the whole buffer' })
  end
  for _, lhs in ipairs(km.jump_to_repl) do
    vim.keymap.set('n', lhs, function()
      M.jump_to_repl()
    end, { desc = 'mep.repl: jump to the REPL window' })
  end
  -- keymaps.jump_back itself is bound per-session, inside ensure_session
  -- — see that function's own comment on why not here via a global
  -- TermOpen autocmd.

  return options
end

--- Test/dev-only: forget every tracked session (does not kill any real
--- job — a real one is left running, matching `mep.dap.session._reset`'s
--- own "kill it too" *not* being needed here since these are ordinary
--- terminal buffers a user would just `:bd!` themselves).
function M._reset()
  state._reset()
end

return M

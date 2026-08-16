--- Debuggee console: a single persistent scratch buffer (`mep.scratch`'s
--- own "one buffer, reused across every open() call" idiom) that
--- accumulates the running session's `output` events, plus `evaluate_
--- interactive` — prompt for an expression (`vim.ui.input`), send it via
--- `mep.dap.session.evaluate`, and append both the expression and its
--- result.
local session = require('mep.dap.session')

local M = {}

local buf, win
local subscribed = false

--- Give MepDapReplTitle a visible default if nothing else already has —
--- same `default = true` reasoning as `mep.dap.breakpoints.define_
--- default_hl`.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, 'MepDapReplTitle', { link = 'Title', default = true })
end
M.define_default_hl()

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mep-dap-repl'
  return buf
end

--- Append `text` (may itself contain embedded `\n`s) as one or more new
--- lines at the end of the console buffer, creating it first if needed.
--- Public (not just used for adapter `output` events) so `mep.dap.
--- session`'s own consumers could log something into the same console
--- if they wanted to.
function M.append(text)
  ensure_buf()
  local new_lines = vim.split(text, '\n', { plain = true })
  local line_count = vim.api.nvim_buf_line_count(buf)
  local is_empty = line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
  if is_empty then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  else
    vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, new_lines)
  end
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end

local function ensure_subscribed()
  if subscribed then
    return
  end
  subscribed = true
  session.subscribe(function(kind, data)
    if kind == 'output' and data and data.output then
      M.append(data.output)
    elseif kind == 'terminated' or kind == 'exited' then
      M.append('[session ended]')
    end
  end)
end

function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- The console's underlying buffer (creating it, but not opening a
--- window for it, if this is the first call) — public so external code
--- (or a test) can inspect its content directly.
function M.panel_buf()
  return ensure_buf()
end

--- Open the console in a real (`botright split`) window below the
--- current one, creating its buffer the first time. Reuses the same
--- buffer/window across calls, same as `mep.scratch.open`.
function M.open()
  ensure_subscribed()
  if M.is_open() then
    return
  end
  ensure_buf()
  vim.cmd('botright split')
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].winbar = '%#MepDapReplTitle# Debug Console'
  pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Prompt (`vim.ui.input`) for an expression, evaluate it in the
--- current frame via `mep.dap.session.evaluate`, and append both the
--- typed expression (`> ...`) and its result (or error message) to the
--- console — opening it first if it wasn't already.
function M.evaluate_interactive()
  vim.ui.input({ prompt = 'mep.dap: evaluate: ' }, function(expression)
    if expression == nil or expression == '' then
      return
    end
    M.open()
    M.append('> ' .. expression)
    session.evaluate(expression, function(resp)
      if resp.success then
        M.append(tostring(resp.body and resp.body.result or ''))
      else
        M.append('error: ' .. tostring(resp.message or 'evaluation failed'))
      end
    end)
  end)
end

--- Test/dev-only: drop the console buffer/window and forget the `mep.
--- dap.session` subscription (so the next `open()`/`append()` builds a
--- fresh buffer instead of reusing whatever a previous test left).
function M._reset()
  if M.is_open() then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  buf, win = nil, nil
  subscribed = false
end

return M

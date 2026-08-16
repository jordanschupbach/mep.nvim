--- Tabstop navigation for one in-flight snippet expansion — extmarks
--- tracking each stop's live span, not a frozen `(row, col)` (the same
--- "extmark, not a frozen position" idiom `mep.ai`'s own stream landing
--- spot uses, adapted from a single tracked point to a tracked range:
--- each tabstop's extmark carries independent start/end gravity —
--- `right_gravity = false` at the start so it stays put, `end_
--- right_gravity = true` at the end so typing inside the stop grows it
--- — rather than `mep.ai`'s own "recompute and re-set the mark by id
--- after every edit", since a range with the right gravity settings
--- tracks itself).
---
--- Only one session is ever active at a time (like `mep.ai`'s own
--- single in-flight stream) — starting a new expansion cancels any
--- current one outright, no stacking/nesting.
local M = {}

local ns = vim.api.nvim_create_namespace('mep_snippet')

-- { bufnr, win, order = { {index, ext_id}, ... }, i }
local session = nil

--- Whether a snippet expansion is currently being navigated.
function M.is_active()
  return session ~= nil
end

--- Abandon the current session (if any), clearing its extmarks. Does
--- not touch buffer text — whatever's currently in the placeholders
--- stays exactly as typed.
function M.cancel()
  if session and vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.api.nvim_buf_clear_namespace(session.bufnr, ns, 0, -1)
  end
  session = nil
end

--- Stable sort of `tabstops` (this module's own `mep.snippet.parse.
--- render` output) by index ascending, with index `0` (the exit point)
--- always last regardless of its textual position — `table.sort` isn't
--- stable, so original order is preserved via an explicit decorate key
--- for tabstops that share an index.
local function sorted_order(tabstops)
  local decorated = {}
  for i, t in ipairs(tabstops) do
    decorated[i] = { t = t, i = i }
  end
  table.sort(decorated, function(a, b)
    local ka = (a.t.index == 0) and math.huge or a.t.index
    local kb = (b.t.index == 0) and math.huge or b.t.index
    if ka ~= kb then
      return ka < kb
    end
    return a.i < b.i
  end)
  local out = {}
  for i, d in ipairs(decorated) do
    out[i] = d.t
  end
  return out
end

--- Expand `body` (a `mep.snippet.parse`-shaped snippet body string) in
--- `bufnr`/`win`, replacing the `replace_len` bytes immediately before
--- the cursor (typically the already-typed trigger word) with the
--- rendered snippet, then jump to its first tabstop. Cancels any
--- currently active session first.
function M.expand(bufnr, win, replace_len, body)
  M.cancel()

  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local start_col = col - replace_len
  local indent = line:match('^%s*') or ''

  local parse = require('mep.snippet.parse')
  local parts = parse.parse(body)
  local rendered_lines, tabstops = parse.render(parts, indent)

  local has_zero = false
  for _, t in ipairs(tabstops) do
    if t.index == 0 then
      has_zero = true
      break
    end
  end
  if not has_zero then
    local last_lnum = #rendered_lines - 1
    local last_col = #rendered_lines[#rendered_lines]
    tabstops[#tabstops + 1] = { index = 0, lnum = last_lnum, col_start = last_col, col_end = last_col }
  end

  local before = line:sub(1, start_col)
  local after = line:sub(col + 1)
  rendered_lines[1] = before .. rendered_lines[1]
  rendered_lines[#rendered_lines] = rendered_lines[#rendered_lines] .. after
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, rendered_lines)

  local order = {}
  for _, t in ipairs(sorted_order(tabstops)) do
    local abs_row = (lnum - 1) + t.lnum
    local col_offset = (t.lnum == 0) and #before or 0
    local ext_id = vim.api.nvim_buf_set_extmark(bufnr, ns, abs_row, t.col_start + col_offset, {
      end_row = abs_row,
      end_col = t.col_end + col_offset,
      right_gravity = false,
      end_right_gravity = true,
    })
    order[#order + 1] = { index = t.index, ext_id = ext_id }
  end

  session = { bufnr = bufnr, win = win, order = order, i = 0 }
  M.jump(1)
end

--- Move to the next (`direction = 1`) or previous (`direction = -1`)
--- tabstop. Landing on the last stop (always the exit point, `$0`, by
--- construction) ends the session. A no-op (returns `false`) if no
--- session is active, or navigation would go past either end.
function M.jump(direction)
  if not session then
    return false
  end
  local new_i = session.i + direction
  if new_i < 1 or new_i > #session.order then
    return false
  end
  session.i = new_i
  local entry = session.order[new_i]
  local pos = vim.api.nvim_buf_get_extmark_by_id(session.bufnr, ns, entry.ext_id, {})
  pcall(vim.api.nvim_win_set_cursor, session.win, { pos[1] + 1, pos[2] })
  if new_i == #session.order then
    M.cancel()
  end
  return true
end

--- Test/dev-only: forget any active session without touching buffer
--- text or extmarks — for state hygiene between specs that never got as
--- far as a real buffer.
function M._reset()
  session = nil
end

return M

--- Org timestamps: active `<2024-01-01 Mon>` and inactive
--- `[2024-01-01 Mon]`, with an optional time (or time range) and
--- repeater (`+1w`, `++1w`, `.+1w`). Pure line-pattern parsing, same
--- style as mep.org.headline — no tree-sitter parser needed (the `org`
--- parser only backs *highlighting*, and its generic `(timestamp)`
--- capture already covers these once inserted; see
--- queries/org/highlights.scm).
local M = {}

local DOW_BY_WDAY = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }

local ACTIVE_PATTERN = '<(%d%d%d%d%-%d%d%-%d%d [^>]*)>'
local INACTIVE_PATTERN = '%[(%d%d%d%d%-%d%d%-%d%d [^%]]*)%]'

local function parse_inner(inner, active)
  local year, month, day, dow, rest = inner:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%a+)(.*)$')
  if not year then
    return nil
  end

  local t = {
    active = active,
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    dow = dow,
  }

  local h1, m1, h2, m2 = rest:match('^ (%d%d):(%d%d)%-(%d%d):(%d%d)')
  if h1 then
    t.hour, t.min, t.end_hour, t.end_min = tonumber(h1), tonumber(m1), tonumber(h2), tonumber(m2)
    rest = rest:gsub('^ %d%d:%d%d%-%d%d:%d%d', '', 1)
  else
    local h, m = rest:match('^ (%d%d):(%d%d)')
    if h then
      t.hour, t.min = tonumber(h), tonumber(m)
      rest = rest:gsub('^ %d%d:%d%d', '', 1)
    end
  end

  local repeater = rest:match('^ ([%+%.]+%d+[hdwmy])')
  if repeater then
    t.repeater = repeater
  end

  return t
end

--- Find the first timestamp in `line` at or after byte index `init`
--- (default 1). Returns `start_col, end_col` (1-based, inclusive) and
--- the parsed timestamp `{ active, year, month, day, dow, hour, min,
--- end_hour, end_min, repeater }`, or nil if there isn't one.
function M.find(line, init)
  init = init or 1
  local as, ae, ainner = line:find(ACTIVE_PATTERN, init)
  local is_, ie, iinner = line:find(INACTIVE_PATTERN, init)

  if as and (not is_ or as <= is_) then
    return as, ae, parse_inner(ainner, true)
  elseif is_ then
    return is_, ie, parse_inner(iinner, false)
  end
  return nil
end

--- Find the timestamp in `line` that contains 0-based column `col`
--- (Neovim cursor convention), or nil.
function M.find_at_col(line, col)
  local init = 1
  while true do
    local s, e, parsed = M.find(line, init)
    if not s then
      return nil
    end
    if col >= s - 1 and col < e then
      return s, e, parsed
    end
    if s - 1 > col then
      return nil
    end
    init = e + 1
  end
end

--- Parse a single standalone timestamp string (e.g. `"<2024-01-01 Mon>"`)
--- in full, or nil if `text` isn't exactly one timestamp.
function M.parse(text)
  local s, e, parsed = M.find(text, 1)
  if s == 1 and e == #text then
    return parsed
  end
  return nil
end

--- Rebuild a timestamp string from parts as returned by `find`/`parse`.
function M.render(t)
  local parts = { string.format('%04d-%02d-%02d %s', t.year, t.month, t.day, t.dow) }
  if t.hour then
    if t.end_hour then
      parts[#parts + 1] = string.format('%02d:%02d-%02d:%02d', t.hour, t.min, t.end_hour, t.end_min)
    else
      parts[#parts + 1] = string.format('%02d:%02d', t.hour, t.min)
    end
  end
  if t.repeater then
    parts[#parts + 1] = t.repeater
  end
  local inner = table.concat(parts, ' ')
  return t.active and ('<' .. inner .. '>') or ('[' .. inner .. ']')
end

--- Today's date as a timestamp table (`active` defaults to true).
function M.today(active)
  local d = os.date('*t')
  return {
    active = active == nil or active,
    year = d.year,
    month = d.month,
    day = d.day,
    dow = DOW_BY_WDAY[d.wday],
  }
end

--- Like `today`, but also fills in the current hour/minute — for
--- mep.org.clock's CLOCK entries, which need a real timestamp, not just
--- a date.
function M.now(active)
  local t = M.today(active)
  local d = os.date('*t')
  t.hour, t.min = d.hour, d.min
  return t
end

--- `t` shifted by `delta` days (negative to go back), recomputing the
--- weekday and rolling over month/year boundaries correctly. Noon is
--- used internally to sidestep DST edge cases.
function M.add_days(t, delta)
  local time = os.time({ year = t.year, month = t.month, day = t.day, hour = 12 })
  local d = os.date('*t', time + delta * 86400)
  local new_t = vim.deepcopy(t)
  new_t.year, new_t.month, new_t.day, new_t.dow = d.year, d.month, d.day, DOW_BY_WDAY[d.wday]
  return new_t
end

--- Render `t` for use as a `vim.ui.input` default/prompt-friendly value:
--- `YYYY-MM-DD` or `YYYY-MM-DD HH:MM` — no brackets, no weekday (the
--- weekday is always recomputed from the date, never taken from user
--- input, so real org-mode never asks for it either).
function M.to_input_string(t)
  local s = string.format('%04d-%02d-%02d', t.year, t.month, t.day)
  if t.hour then
    s = s .. string.format(' %02d:%02d', t.hour, t.min)
  end
  return s
end

--- Parse a `to_input_string`-shaped user-entered string (`YYYY-MM-DD` or
--- `YYYY-MM-DD HH:MM`) into a timestamp table with `active` set and the
--- weekday freshly computed, or nil if `text` doesn't match.
function M.parse_user_input(text, active)
  local date_part, time_part = text:match('^%s*(%S+)%s*(%S*)%s*$')
  if not date_part then
    return nil
  end
  local year, month, day = date_part:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$')
  if not year then
    return nil
  end
  year, month, day = tonumber(year), tonumber(month), tonumber(day)

  local t = { active = active, year = year, month = month, day = day }
  if time_part ~= '' then
    local hour, min = time_part:match('^(%d%d?):(%d%d)$')
    if not hour then
      return nil
    end
    t.hour, t.min = tonumber(hour), tonumber(min)
  end
  t.dow = DOW_BY_WDAY[os.date('*t', os.time({ year = year, month = month, day = day, hour = 12 })).wday]
  return t
end

--- Insert a new timestamp at the cursor, or edit the one the cursor is
--- already inside — interactive, via `vim.ui.input` (prompt pre-filled
--- with the existing date when editing, today's date otherwise).
--- `active` (default true) controls active vs. inactive for a *new*
--- timestamp; editing an existing one always preserves its own
--- active/inactive-ness regardless of `active`.
function M.insert_or_edit(bufnr, win, active)
  if active == nil then
    active = true
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local s, e, existing = M.find_at_col(line, col)

  local default = M.to_input_string(existing or M.today(active))
  vim.ui.input({ prompt = 'Timestamp (YYYY-MM-DD [HH:MM]): ', default = default }, function(text)
    if not text then
      return
    end
    -- NOT `existing and existing.active or active`: that idiom breaks
    -- when existing.active is false (a real, falsy boolean, not nil) --
    -- `x and false or y` evaluates to `y`, silently flipping an edited
    -- inactive timestamp active.
    local target_active = active
    if existing then
      target_active = existing.active
    end
    local parsed = M.parse_user_input(text, target_active)
    if not parsed then
      return
    end
    local rendered = M.render(parsed)
    local current = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
    if s then
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { current:sub(1, s - 1) .. rendered .. current:sub(e + 1) })
    else
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { current:sub(1, col) .. rendered .. current:sub(col + 1) })
    end
  end)
end

--- Adjust the timestamp under the cursor by `delta` days (negative to go
--- back; pass 7/-7 for a week). Returns true if a timestamp was found
--- and adjusted, false otherwise — callers should fall back to normal
--- `<C-a>`/`<C-x>` behavior on false, since this is meant to shadow
--- those keys only while the cursor is actually on a timestamp.
function M.adjust_under_cursor(bufnr, win, delta)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local s, e, parsed = M.find_at_col(line, col)
  if not s then
    return false
  end
  local rendered = M.render(M.add_days(parsed, delta))
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line:sub(1, s - 1) .. rendered .. line:sub(e + 1) })
  return true
end

return M

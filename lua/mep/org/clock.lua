--- Clocking: `CLOCK:` entries in a headline's `:LOGBOOK:` drawer (right
--- after its planning line and `:PROPERTIES:` drawer, before body text),
--- clock-in/out commands, a statusline-friendly status string, effort
--- estimates (an `Effort:` property), and a clock-table report.
---
--- The "currently clocked-in" task is found by scanning the buffer for
--- an *open* `CLOCK:` line (no `--end => duration` yet) rather than
--- tracked as session-only state — slower for a huge file, but correct
--- across buffer reloads and Neovim restarts, which session state alone
--- wouldn't be.
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')
local plan_mod = require('mep.org.plan')
local property = require('mep.org.property')
local timestamp = require('mep.org.timestamp')

local M = {}

local LOGBOOK_START = '^%s*:LOGBOOK:%s*$'
local LOGBOOK_END = '^%s*:END:%s*$'
local CLOCK_OPEN = '^%s*CLOCK:%s*(%[[^%]]*%])%s*$'
local CLOCK_CLOSED = '^%s*CLOCK:%s*%[[^%]]*%]%-%-%[[^%]]*%]%s*=>%s*(%d+):(%d%d)%s*$'

--- The `:LOGBOOK:` drawer line range for the headline at
--- `headline_lnum`: `start_lnum, end_lnum` (1-based, inclusive of the
--- `:LOGBOOK:`/`:END:` lines), or nil if it has none.
function M.find_logbook(bufnr, headline_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pstart, pstop = property.find(bufnr, headline_lnum)
  local j
  if pstart then
    j = pstop + 1
  else
    j = headline_lnum + 1
    if lines[j] and plan_mod.is_plan_line(lines[j]) then
      j = j + 1
    end
  end
  if not (lines[j] and lines[j]:match(LOGBOOK_START)) then
    return nil
  end
  local start = j
  local k = j + 1
  while lines[k] and not lines[k]:match(LOGBOOK_END) do
    k = k + 1
  end
  if lines[k] then
    return start, k
  end
  return nil
end

--- The buffer position right after the headline at `headline_lnum`'s
--- planning line and properties drawer (i.e. where a `:LOGBOOK:` drawer
--- belongs if it doesn't exist yet) — a 0-indexed `nvim_buf_set_lines`
--- insertion point (numerically equal to the 1-based line number of
--- whatever it should come right after: the headline, its planning
--- line, or its properties drawer's `:END:`).
local function content_start(bufnr, headline_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local insert_at = headline_lnum
  if lines[headline_lnum + 1] and plan_mod.is_plan_line(lines[headline_lnum + 1]) then
    insert_at = headline_lnum + 1
  end
  local pstart, pstop = property.find(bufnr, headline_lnum)
  if pstart then
    insert_at = pstop
  end
  return insert_at
end

--- The currently open clock, anywhere in `bufnr`: `{ lnum, start_text,
--- headline }` (`start_text` is the raw `[...]` timestamp text,
--- `headline` the line number of the headline it belongs to, or nil if
--- the open CLOCK line isn't under any headline), or nil if nothing is
--- clocked in.
function M.current_clock(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local start_text = line:match(CLOCK_OPEN)
    if start_text then
      return { lnum = i, start_text = start_text, headline = outline.current_headline(bufnr, i) }
    end
  end
  return nil
end

--- Whole minutes between timestamp tables `t1` and `t2` (`t2` after
--- `t1`; a negative result if not).
function M.diff_minutes(t1, t2)
  local time1 = os.time({ year = t1.year, month = t1.month, day = t1.day, hour = t1.hour or 0, min = t1.min or 0 })
  local time2 = os.time({ year = t2.year, month = t2.month, day = t2.day, hour = t2.hour or 0, min = t2.min or 0 })
  return math.floor((time2 - time1) / 60)
end

--- Render whole `minutes` as `"H:MM"`.
local function format_minutes(minutes)
  return string.format('%d:%02d', math.floor(minutes / 60), minutes % 60)
end

--- Clock in on the headline containing `lnum`: adds an open `CLOCK:
--- [now]` entry as the first line of its `:LOGBOOK:` drawer, creating
--- the drawer if needed. Refuses (returns nil) if something is already
--- clocked in anywhere in the buffer — real org-mode only ever tracks
--- one active clock at a time.
function M.clock_in(bufnr, lnum)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  if M.current_clock(bufnr) then
    return nil
  end

  local clock_line = 'CLOCK: ' .. timestamp.render(timestamp.now(false))
  local start, _ = M.find_logbook(bufnr, at)
  if start then
    vim.api.nvim_buf_set_lines(bufnr, start, start, false, { clock_line })
  else
    local insert_at = content_start(bufnr, at)
    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { ':LOGBOOK:', clock_line, ':END:' })
  end
  return clock_line
end

--- Clock out of whatever is currently clocked in (anywhere in `bufnr`):
--- closes the open `CLOCK:` line with an end timestamp and duration.
--- Returns the duration as `"H:MM"`, or nil if nothing is clocked in.
function M.clock_out(bufnr)
  local clock = M.current_clock(bufnr)
  if not clock then
    return nil
  end
  local start_ts = timestamp.parse(clock.start_text)
  local end_ts = timestamp.now(false)
  local duration = format_minutes(M.diff_minutes(start_ts, end_ts))
  local rendered = 'CLOCK: ' .. clock.start_text .. '--' .. timestamp.render(end_ts) .. ' => ' .. duration
  vim.api.nvim_buf_set_lines(bufnr, clock.lnum - 1, clock.lnum, false, { rendered })
  return duration
end

--- A statusline-friendly string for whatever is currently clocked in
--- (`"Headline title (H:MM)"`), or nil if nothing is. Not tied to any
--- particular statusline plugin — call this from your own 'statusline'
--- (e.g. `%{v:lua.require'mep.org.clock'.status(0)}`).
function M.status(bufnr, todo_keywords)
  local clock = M.current_clock(bufnr)
  if not clock or not clock.headline then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, clock.headline - 1, clock.headline, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})
  local minutes = M.diff_minutes(timestamp.parse(clock.start_text), timestamp.now(false))
  return string.format('%s (%s)', parsed.title, format_minutes(minutes))
end

--- Parse an effort/duration value (`"H:MM"` or bare minutes) into whole
--- minutes, or nil if `text` doesn't match either form.
function M.parse_duration(text)
  if not text then
    return nil
  end
  local h, m = text:match('^(%d+):(%d%d)$')
  if h then
    return tonumber(h) * 60 + tonumber(m)
  end
  local mins = text:match('^(%d+)$')
  if mins then
    return tonumber(mins)
  end
  return nil
end

--- The headline containing `lnum`'s `Effort:` property, in minutes, or
--- nil if it has none / isn't a valid duration.
function M.effort(bufnr, lnum)
  return M.parse_duration(property.get(bufnr, lnum, 'Effort'))
end

--- Every headline in `bufnr` with clocked time, as a list of `{ lnum,
--- level, title, minutes }` (`minutes` is the *recursive* total: its own
--- closed clock entries plus every descendant's), ordered by line
--- number. Headlines with no clocked time anywhere in their subtree are
--- omitted.
function M.report(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local own_minutes = {}
  for i, line in ipairs(lines) do
    local h, m = line:match(CLOCK_CLOSED)
    if h then
      local headline_lnum = outline.current_headline(bufnr, i)
      if headline_lnum then
        own_minutes[headline_lnum] = (own_minutes[headline_lnum] or 0) + tonumber(h) * 60 + tonumber(m)
      end
    end
  end

  local rows = {}
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      local stop = outline.subtree_end(bufnr, i)
      local total = 0
      for j = i, stop do
        total = total + (own_minutes[j] or 0)
      end
      if total > 0 then
        local parsed = headline_mod.parse(line, {})
        rows[#rows + 1] = { lnum = i, level = parsed.level, title = parsed.title, minutes = total }
      end
    end
  end
  return rows
end

--- Render `rows` (as from `report`) into `#+BEGIN: clocktable ... #+END:`
--- block lines, indenting each title by its level.
function M.render_table(rows)
  local out = { '#+BEGIN: clocktable', '| Headline | Time |', '|--' }
  for _, r in ipairs(rows) do
    out[#out + 1] = string.format('| %s%s | %s |', string.rep('  ', r.level - 1), r.title, format_minutes(r.minutes))
  end
  out[#out + 1] = '#+END:'
  return out
end

--- The line range of an existing `#+BEGIN: clocktable ... #+END:` block
--- at or after `lnum`, or nil.
function M.find_clocktable(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = lnum, #lines do
    if lines[i]:match('^%s*#%+BEGIN:%s*clocktable') then
      local j = i + 1
      while lines[j] and not lines[j]:match('^%s*#%+END:%s*$') do
        j = j + 1
      end
      if lines[j] then
        return i, j
      end
    end
  end
  return nil
end

--- Insert (or refresh, if one already exists at/after `lnum`) a
--- clock-table report at `lnum`.
function M.insert_report(bufnr, lnum)
  local rendered = M.render_table(M.report(bufnr))
  local start, stop = M.find_clocktable(bufnr, lnum)
  if start then
    vim.api.nvim_buf_set_lines(bufnr, start - 1, stop, false, rendered)
  else
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, rendered)
  end
end

return M

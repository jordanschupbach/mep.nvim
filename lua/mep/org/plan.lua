--- SCHEDULED:/DEADLINE: planning lines: the line immediately after a
--- headline (before any body text/property drawer) carrying one or both
--- of `SCHEDULED: <...>` / `DEADLINE: <...>`. Pure line-pattern parsing,
--- delegating timestamp text itself to mep.org.timestamp.
local timestamp = require('mep.org.timestamp')
local outline = require('mep.org.outline')

local M = {}

--- Whether `line` is a planning line at all (fast path; use `parse` to
--- get its parts).
function M.is_plan_line(line)
  return line ~= nil and (line:match('^%s*SCHEDULED:') ~= nil or line:match('^%s*DEADLINE:') ~= nil)
end

--- Parse a planning line into `{ scheduled = <timestamp text>, deadline
--- = <timestamp text> }` (a key is omitted if that part isn't present),
--- or nil if `line` isn't a planning line.
function M.parse(line)
  if not M.is_plan_line(line) then
    return nil
  end
  local plan = {}
  plan.scheduled = line:match('SCHEDULED:%s*(<[^>]*>)') or line:match('SCHEDULED:%s*(%[[^%]]*%])')
  plan.deadline = line:match('DEADLINE:%s*(<[^>]*>)') or line:match('DEADLINE:%s*(%[[^%]]*%])')
  return plan
end

--- Rebuild a planning line from `{ scheduled = ..., deadline = ... }`.
--- Returns `""` if neither is set.
function M.render(plan)
  local parts = {}
  if plan.scheduled then
    parts[#parts + 1] = 'SCHEDULED: ' .. plan.scheduled
  end
  if plan.deadline then
    parts[#parts + 1] = 'DEADLINE: ' .. plan.deadline
  end
  return table.concat(parts, ' ')
end

--- The line number of the planning line immediately after the headline
--- at `headline_lnum`, if there is one, else nil.
function M.find(bufnr, headline_lnum)
  local next_lnum = headline_lnum + 1
  local line = vim.api.nvim_buf_get_lines(bufnr, next_lnum - 1, next_lnum, false)[1]
  if M.is_plan_line(line) then
    return next_lnum
  end
  return nil
end

local function set_field(bufnr, lnum, field, timestamp_text)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local plan_lnum = M.find(bufnr, at)
  local plan = plan_lnum and M.parse(vim.api.nvim_buf_get_lines(bufnr, plan_lnum - 1, plan_lnum, false)[1]) or {}
  plan[field] = timestamp_text
  local rendered = M.render(plan)

  if plan_lnum then
    if rendered == '' then
      vim.api.nvim_buf_set_lines(bufnr, plan_lnum - 1, plan_lnum, false, {})
    else
      vim.api.nvim_buf_set_lines(bufnr, plan_lnum - 1, plan_lnum, false, { rendered })
    end
  elseif rendered ~= '' then
    vim.api.nvim_buf_set_lines(bufnr, at, at, false, { rendered })
  end
  return timestamp_text
end

--- Set (creating the planning line if needed) the SCHEDULED timestamp on
--- the headline containing `lnum`. `timestamp_text` is a full rendered
--- timestamp string (e.g. from `mep.org.timestamp.render`). Returns
--- `timestamp_text`, or nil if `lnum` isn't inside a headline.
function M.set_scheduled(bufnr, lnum, timestamp_text)
  return set_field(bufnr, lnum, 'scheduled', timestamp_text)
end

--- Like `set_scheduled`, for DEADLINE.
function M.set_deadline(bufnr, lnum, timestamp_text)
  return set_field(bufnr, lnum, 'deadline', timestamp_text)
end

--- Remove the SCHEDULED part (deleting the planning line entirely if it
--- had nothing else).
function M.remove_scheduled(bufnr, lnum)
  return set_field(bufnr, lnum, 'scheduled', nil)
end

--- Like `remove_scheduled`, for DEADLINE.
function M.remove_deadline(bufnr, lnum)
  return set_field(bufnr, lnum, 'deadline', nil)
end

local function get_field(bufnr, lnum, field)
  local at = outline.current_headline(bufnr, lnum)
  local plan_lnum = at and M.find(bufnr, at)
  if not plan_lnum then
    return nil
  end
  local plan = M.parse(vim.api.nvim_buf_get_lines(bufnr, plan_lnum - 1, plan_lnum, false)[1])
  return plan and plan[field]
end

--- The SCHEDULED timestamp text on the headline containing `lnum`, or
--- nil if there isn't one.
function M.get_scheduled(bufnr, lnum)
  return get_field(bufnr, lnum, 'scheduled')
end

--- Like `get_scheduled`, for DEADLINE.
function M.get_deadline(bufnr, lnum)
  return get_field(bufnr, lnum, 'deadline')
end

local function interactive(bufnr, win, lnum, getter, setter, label)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return
  end
  local existing_text = getter(bufnr, at)
  local existing = existing_text and timestamp.parse(existing_text)
  local default = timestamp.to_input_string(existing or timestamp.today(true))
  vim.ui.input({ prompt = label .. ' (YYYY-MM-DD [HH:MM]): ', default = default }, function(text)
    if not text then
      return
    end
    local parsed = timestamp.parse_user_input(text, true)
    if not parsed then
      return
    end
    setter(bufnr, at, timestamp.render(parsed))
  end)
end

--- Interactively set the SCHEDULED timestamp on the headline containing
--- `lnum`, prompting via `vim.ui.input` (real org-mode's `org-schedule`,
--- `C-c C-s`).
function M.schedule_interactive(bufnr, win, lnum)
  interactive(bufnr, win, lnum, M.get_scheduled, M.set_scheduled, 'Schedule for')
end

--- Like `schedule_interactive`, for DEADLINE (real org-mode's
--- `org-deadline`, `C-c C-d`).
function M.deadline_interactive(bufnr, win, lnum)
  interactive(bufnr, win, lnum, M.get_deadline, M.set_deadline, 'Deadline for')
end

return M

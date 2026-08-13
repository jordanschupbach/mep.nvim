--- Agenda: aggregates scheduled/deadline items, TODO state, and tags
--- across every configured `agenda_files` file into one buffer — real
--- org-mode's `org-agenda`, `C-c a`. The single biggest remaining "core"
--- feature, and the one most dependent on earlier phases actually
--- existing: mep.org.timestamp/plan (Phase 3) for dates, mep.org.tags/
--- tagmatch (Phase 4) for tag search, mep.org.property (Phase 7) is
--- available to a future phase for property search.
---
--- Like mep.org.capture, real org-agenda is a *global* command (any
--- buffer). This project only activates keymaps inside org buffers, so
--- `dispatch_interactive` is bound there too for discoverability, but is
--- a plain function — bind it to a global keymap yourself for the real
--- "agenda from anywhere" experience.
local headline_mod = require('mep.org.headline')
local plan_mod = require('mep.org.plan')
local timestamp_mod = require('mep.org.timestamp')
local tags_mod = require('mep.org.tags')
local todo_mod = require('mep.org.todo')

local M = {}

--- Resolve `agenda_files` (a list of literal paths and/or glob patterns,
--- e.g. `{'~/notes/todo.org', '~/notes/projects/*.org'}`) into a flat,
--- sorted, deduped list of actual file paths.
function M.files(agenda_files)
  local seen = {}
  local out = {}
  for _, pattern in ipairs(agenda_files or {}) do
    -- `glob()` itself expands `~`/env vars *and* wildcards correctly;
    -- pre-expanding with `expand()` first breaks it, since `expand()` on
    -- a wildcard pattern already resolves it into a newline-joined
    -- string of matches, which `glob()` then can't re-parse as a pattern.
    local matches = vim.fn.glob(pattern, false, true)
    if #matches == 0 then
      local expanded_pattern = vim.fn.expand(pattern)
      if vim.fn.filereadable(expanded_pattern) == 1 then
        matches = { expanded_pattern }
      end
    end
    for _, path in ipairs(matches) do
      if not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  table.sort(out)
  return out
end

--- Load `path` into a buffer without displaying it, reusing an
--- already-open buffer's live (possibly unsaved) content if there is
--- one — same idiom `mep.org.capture` uses for its target file, so the
--- agenda reflects in-progress edits, not just what's on disk.
local function load_buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end

--- Every headline in `bufnr` as an entry: `{ bufnr, file, lnum, todo,
--- title, level, tags (effective, inheritance-aware), scheduled,
--- deadline }` (`scheduled`/`deadline` are parsed timestamp tables, or
--- nil).
local function collect_from_buffer(bufnr, path, todo_keywords)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = {}
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      local parsed = headline_mod.parse(line, todo_keywords or {})
      local plan_lnum = plan_mod.find(bufnr, i)
      local scheduled, deadline
      if plan_lnum then
        local p = plan_mod.parse(lines[plan_lnum])
        if p.scheduled then
          scheduled = timestamp_mod.parse(p.scheduled)
        end
        if p.deadline then
          deadline = timestamp_mod.parse(p.deadline)
        end
      end
      entries[#entries + 1] = {
        bufnr = bufnr,
        file = path,
        lnum = i,
        todo = parsed.todo,
        title = parsed.title,
        level = parsed.level,
        tags = tags_mod.effective_tags(bufnr, i, todo_keywords),
        scheduled = scheduled,
        deadline = deadline,
      }
    end
  end
  return entries
end

--- Every headline across `files` as entries (see `collect_from_buffer`).
function M.collect_entries(files, todo_keywords)
  local entries = {}
  for _, path in ipairs(files) do
    vim.list_extend(entries, collect_from_buffer(load_buf(path), path, todo_keywords))
  end
  return entries
end

--- `t` (a timestamp table) as a whole-day integer key, for date-only
--- (not time-of-day) comparison — noon avoids DST edge cases, matching
--- `mep.org.timestamp.add_days`'s own convention.
local function date_key(t)
  return math.floor(os.time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end

--- Whether `target` (a timestamp table) is an occurrence of `base`'s
--- (a timestamp table) `repeater` (e.g. `"+1w"`), or is exactly `base`
--- itself. Handles day/week/month/year units. All three repeater
--- cadence variants (`+`/`++`/`.+`) are treated identically here — a
--- deliberate simplification; `.+` in particular really means "N units
--- after whenever this was last *completed*", which needs
--- completion-history tracking this project doesn't have.
function M.occurs_on(base, target, repeater)
  if date_key(base) == date_key(target) then
    return true
  end
  if not repeater or date_key(target) < date_key(base) then
    return false
  end
  local n, unit = repeater:match('[%+%.]+(%d+)([dwmy])')
  n = tonumber(n)
  if not n or n < 1 then
    return false
  end

  if unit == 'd' then
    return (date_key(target) - date_key(base)) % n == 0
  elseif unit == 'w' then
    return (date_key(target) - date_key(base)) % (n * 7) == 0
  elseif unit == 'm' then
    if target.day ~= base.day then
      return false
    end
    local months = (target.year - base.year) * 12 + (target.month - base.month)
    return months >= 0 and months % n == 0
  elseif unit == 'y' then
    if target.day ~= base.day or target.month ~= base.month then
      return false
    end
    return (target.year - base.year) % n == 0
  end
  return false
end

--- Every occurrence of `entries` landing on `date`: a list of
--- `{ entry, kind = 'scheduled'|'deadline', days_until }` (`days_until`
--- is 0 for something actually due/scheduled on `date`, positive for a
--- deadline-warning entry that many days out, negative for an overdue
--- deadline). `warning_days` (optional) includes upcoming deadlines that
--- many days ahead; `include_overdue` (optional) also includes
--- non-repeating deadlines already in the past relative to `date` — only
--- meaningful when `date` is "today", not when browsing another day.
function M.entries_for_date(entries, date, warning_days, include_overdue)
  local occurrences = {}
  for _, e in ipairs(entries) do
    if e.scheduled and M.occurs_on(e.scheduled, date, e.scheduled.repeater) then
      occurrences[#occurrences + 1] = { entry = e, kind = 'scheduled', days_until = 0 }
    end
    if e.deadline then
      if M.occurs_on(e.deadline, date, e.deadline.repeater) then
        occurrences[#occurrences + 1] = { entry = e, kind = 'deadline', days_until = 0 }
      elseif warning_days and warning_days > 0 then
        local days_until = date_key(e.deadline) - date_key(date)
        if days_until > 0 and days_until <= warning_days then
          occurrences[#occurrences + 1] = { entry = e, kind = 'deadline', days_until = days_until }
        end
      end
      if include_overdue and not e.deadline.repeater then
        local days_until = date_key(e.deadline) - date_key(date)
        if days_until < 0 then
          occurrences[#occurrences + 1] = { entry = e, kind = 'deadline', days_until = days_until }
        end
      end
    end
  end
  return occurrences
end

--- Every entry with a TODO keyword, excluding the "done" one (the last
--- entry of `todo_keywords`) — real org-mode's global TODO list is
--- conceptually "outstanding work", and this project already treats the
--- last configured keyword as "done" everywhere else (mep.org.statistics
--- etc.), so this follows that same established convention.
function M.todo_view(entries, todo_keywords)
  local done_kw = todo_keywords and todo_keywords[#todo_keywords]
  local out = {}
  for _, e in ipairs(entries) do
    if e.todo and e.todo ~= done_kw then
      out[#out + 1] = e
    end
  end
  return out
end

--- Every entry whose effective tags satisfy `mep.org.tagmatch` `expr`.
--- Returns `{}` (not an error) for an invalid expression.
function M.tag_search_view(entries, expr)
  local tagmatch = require('mep.org.tagmatch')
  local groups = tagmatch.parse(expr)
  if not groups then
    return {}
  end
  local out = {}
  for _, e in ipairs(entries) do
    if tagmatch.matches(groups, e.tags) then
      out[#out + 1] = e
    end
  end
  return out
end

--- `date` as `"Weekday, YYYY-MM-DD"`.
local function format_date_header(date)
  return os.date('%A, %Y-%m-%d', os.time({ year = date.year, month = date.month, day = date.day, hour = 12 }))
end

local function format_occurrence_line(occ)
  local e = occ.entry
  local marker
  if occ.kind == 'deadline' then
    if occ.days_until < 0 then
      marker = string.format('Deadline (%dd overdue):', -occ.days_until)
    elseif occ.days_until > 0 then
      marker = string.format('Deadline in %dd:', occ.days_until)
    else
      marker = 'Deadline:'
    end
  else
    marker = 'Scheduled:'
  end
  local todo_part = e.todo and (e.todo .. ' ') or ''
  return string.format('  %-24s %s%s', marker, todo_part, e.title)
end

--- Render a day view: `date`'s header line, then one line per
--- occurrence (or a placeholder if there are none). Returns `lines`
--- and a parallel `sources` list (`sources[i] = { bufnr, lnum }` for a
--- jumpable entry line, or `false` for a header/placeholder line).
function M.render_day(date, occurrences)
  local lines = { format_date_header(date) }
  local sources = { false }
  if #occurrences == 0 then
    lines[#lines + 1] = '  (nothing scheduled)'
    sources[#sources + 1] = false
  end
  for _, occ in ipairs(occurrences) do
    lines[#lines + 1] = format_occurrence_line(occ)
    sources[#sources + 1] = { bufnr = occ.entry.bufnr, lnum = occ.entry.lnum }
  end
  return lines, sources
end

--- Render a week view starting at `start_date` (7 days): one
--- `render_day`-shaped block per day, concatenated.
function M.render_week(start_date, entries, warning_days)
  local lines, sources = {}, {}
  for i = 0, 6 do
    local d = timestamp_mod.add_days(start_date, i)
    local occ = M.entries_for_date(entries, d, warning_days)
    local day_lines, day_sources = M.render_day(d, occ)
    vim.list_extend(lines, day_lines)
    vim.list_extend(sources, day_sources)
  end
  return lines, sources
end

--- Render a flat list of entries (todo/tag-search views): one line per
--- entry, `"TODO Title  (file:line)"`.
function M.render_entries(entries)
  local lines, sources = {}, {}
  for _, e in ipairs(entries) do
    local todo_part = e.todo and (e.todo .. ' ') or ''
    local tags_part = #e.tags > 0 and ('  :' .. table.concat(e.tags, ':') .. ':') or ''
    lines[#lines + 1] = string.format('%s%s%s  (%s:%d)', todo_part, e.title, tags_part, vim.fn.fnamemodify(e.file, ':t'), e.lnum)
    sources[#sources + 1] = { bufnr = e.bufnr, lnum = e.lnum }
  end
  return lines, sources
end

--- Open a scratch agenda buffer (filetype `org-agenda`) in a new bottom
--- split showing `lines`, with `sources[i]` (from a `render_*`
--- function) driving per-line actions: `<CR>` closes the agenda and
--- jumps to the entry's source; `t` cycles its TODO state in place; `s`
--- schedules it (`mep.org.plan.schedule_interactive`); `q` closes the
--- agenda. `opts.refresh` (optional), if given, is called after `t`/`s`
--- to rebuild `lines, sources` and redraw in place.
function M.open(lines, sources, opts)
  opts = opts or {}
  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd('botright new')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(win, math.min(#lines + 1, 20))

  local buf = vim.api.nvim_win_get_buf(win)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'org-agenda'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local function current_source()
    return sources[vim.api.nvim_win_get_cursor(win)[1]]
  end

  local function redraw()
    if not opts.refresh then
      return
    end
    local new_lines, new_sources = opts.refresh()
    lines, sources = new_lines, new_sources
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<CR>', function()
    local src = current_source()
    if not src then
      return
    end
    pcall(vim.api.nvim_win_close, win, true)
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    vim.api.nvim_win_set_buf(0, src.bufnr)
    vim.api.nvim_win_set_cursor(0, { src.lnum, 0 })
  end, map_opts)

  vim.keymap.set('n', 't', function()
    local src = current_source()
    if not src then
      return
    end
    todo_mod.cycle(src.bufnr, src.lnum, opts.todo_keywords)
    redraw()
  end, map_opts)

  vim.keymap.set('n', 's', function()
    local src = current_source()
    if not src then
      return
    end
    plan_mod.schedule_interactive(src.bufnr, win, src.lnum)
  end, map_opts)

  vim.keymap.set('n', 'q', function()
    pcall(vim.api.nvim_win_close, win, true)
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end, map_opts)

  return buf, win
end

--- Show today's (or `date`'s, if given) agenda.
function M.show_day(config, date)
  date = date or timestamp_mod.today(true)
  local files = M.files(config.agenda_files)
  local is_today = date_key(date) == date_key(timestamp_mod.today(true))
  local function build()
    local entries = M.collect_entries(files, config.todo_keywords)
    local occ = M.entries_for_date(entries, date, config.deadline_warning_days, is_today)
    return M.render_day(date, occ)
  end
  local lines, sources = build()
  M.open(lines, sources, { todo_keywords = config.todo_keywords, refresh = build })
end

--- Show the 7-day agenda starting today (or at `start_date`, if given).
function M.show_week(config, start_date)
  start_date = start_date or timestamp_mod.today(true)
  local files = M.files(config.agenda_files)
  local function build()
    local entries = M.collect_entries(files, config.todo_keywords)
    return M.render_week(start_date, entries, config.deadline_warning_days)
  end
  local lines, sources = build()
  M.open(lines, sources, { todo_keywords = config.todo_keywords, refresh = build })
end

--- Show the global TODO list (every outstanding TODO-stated headline).
function M.show_todo_list(config)
  local files = M.files(config.agenda_files)
  local function build()
    local entries = M.collect_entries(files, config.todo_keywords)
    return M.render_entries(M.todo_view(entries, config.todo_keywords))
  end
  local lines, sources = build()
  M.open(lines, sources, { todo_keywords = config.todo_keywords, refresh = build })
end

--- Show every entry matching a tag-match `expr` (see `mep.org.tagmatch`)
--- across `agenda_files`.
function M.show_tag_search(config, expr)
  local files = M.files(config.agenda_files)
  local function build()
    local entries = M.collect_entries(files, config.todo_keywords)
    return M.render_entries(M.tag_search_view(entries, expr))
  end
  local lines, sources = build()
  M.open(lines, sources, { todo_keywords = config.todo_keywords, refresh = build })
end

--- Prompt for a tag-match expression via `vim.ui.input`, then
--- `show_tag_search`.
function M.show_tag_search_interactive(config)
  vim.ui.input({ prompt = 'Agenda tag match (e.g. +work-urgent): ' }, function(expr)
    if not expr or expr == '' then
      return
    end
    M.show_tag_search(config, expr)
  end)
end

--- Prompt for an agenda view (day/week/todo/tags) via `vim.ui.select`,
--- then open it — real org-mode's `org-agenda` (`C-c a`) similarly asks
--- for a view before showing anything.
function M.dispatch_interactive(config)
  vim.ui.select({ 'day', 'week', 'todo', 'tags' }, { prompt = 'Agenda:' }, function(choice)
    if choice == 'day' then
      M.show_day(config)
    elseif choice == 'week' then
      M.show_week(config)
    elseif choice == 'todo' then
      M.show_todo_list(config)
    elseif choice == 'tags' then
      M.show_tag_search_interactive(config)
    end
  end)
end

return M

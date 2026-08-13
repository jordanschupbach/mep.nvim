--- Plain org lists: bulleted (`-`/`+`/indented `*`) and ordered
--- (`1.`/`1)`) items. Pure line-pattern parsing, same style as
--- mep.org.headline. A `*` bullet must be indented (at least one leading
--- space) to disambiguate from a column-0 headline, matching real
--- org-mode's own rule; `-`/`+` bullets have no such restriction since
--- they never collide with headline syntax.
local checkbox_mod = require('mep.org.checkbox')

local M = {}

local ORDERED = '^(%s*)(%d+)([%.%)])%s+(.*)$'
local DASH_PLUS_BULLET = '^(%s*)([%-%+])%s+(.*)$'
local STAR_BULLET = '^(%s+)(%*)%s+(.*)$'

--- Parse a list-item line into `{ indent, kind, marker, number, sep,
--- content }` (`kind` is `'ordered'` or `'bullet'`; ordered items have
--- `number`/`sep`, bullet items have `marker`), or nil if `line` isn't a
--- list item.
function M.parse(line)
  local indent, num, sep, content = line:match(ORDERED)
  if indent then
    return { indent = indent, kind = 'ordered', number = tonumber(num), sep = sep, content = content }
  end
  local dindent, marker, dcontent = line:match(DASH_PLUS_BULLET)
  if dindent then
    return { indent = dindent, kind = 'bullet', marker = marker, content = dcontent }
  end
  local sindent, smarker, scontent = line:match(STAR_BULLET)
  if sindent then
    return { indent = sindent, kind = 'bullet', marker = smarker, content = scontent }
  end
  return nil
end

--- Whether `line` is a list item at all (fast path; use `parse` to get
--- its parts).
function M.is_list_item(line)
  return M.parse(line) ~= nil
end

--- Render a marker (e.g. `"- "`, `"3. "`) for `item` (as returned by
--- `parse`), without its content.
local function render_marker(item)
  if item.kind == 'ordered' then
    return item.indent .. item.number .. item.sep .. ' '
  end
  return item.indent .. item.marker .. ' '
end

--- Renumber the contiguous run of ordered-list siblings (same indent,
--- same kind) starting at the first one at or before `lnum`, sequentially
--- from 1. Deliberately simpler than real org-mode: the run must be
--- perfectly contiguous (no blank-line gaps tolerated), and always
--- restarts from 1 rather than preserving a non-1 starting number.
--- Returns the number of items renumbered, or nil if `lnum` isn't inside
--- an ordered list.
local function indent_len_of(line)
  return #(line:match('^(%s*)') or '')
end

function M.renumber(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local item = M.parse(lines[lnum] or '')
  if not item or item.kind ~= 'ordered' then
    return nil
  end
  local indent_len = #item.indent

  -- A more-deeply-indented line (nested list / continuation text) is
  -- part of the sibling above it, not a run-breaking sibling itself —
  -- skip over those in both directions rather than stopping at them.
  local first = lnum
  while first > 1 do
    local prev_line = lines[first - 1]
    local prev = M.parse(prev_line)
    if prev and prev.kind == 'ordered' and prev.indent == item.indent then
      first = first - 1
    elseif prev_line ~= '' and indent_len_of(prev_line) > indent_len then
      first = first - 1
    else
      break
    end
  end

  local n = 0
  local i = first
  while lines[i] do
    local it = M.parse(lines[i])
    if it and it.kind == 'ordered' and it.indent == item.indent then
      n = n + 1
      local rendered = item.indent .. n .. it.sep .. ' ' .. it.content
      if rendered ~= lines[i] then
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { rendered })
      end
      i = i + 1
    elseif lines[i] ~= '' and indent_len_of(lines[i]) > indent_len then
      i = i + 1
    else
      break
    end
  end
  return n
end

--- Shift the list item at `lnum`, and any more-deeply-indented
--- continuation lines directly beneath it, by one indent unit (2
--- spaces). `direction > 0` indents, `direction < 0` outdents (refused
--- at zero indent — nothing to outdent to). Continuation lines are
--- everything immediately after `lnum` indented more than the item's own
--- indent, stopping at the first line that isn't (no blank-line
--- tolerance, matching mep.org.sort's sibling-scoping simplicity).
--- Returns the number of lines shifted, or nil if `lnum` isn't a list
--- item or an outdent was refused.
function M.shift_item(bufnr, lnum, direction)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local item = M.parse(lines[lnum] or '')
  if not item then
    return nil
  end
  if direction < 0 and item.indent == '' then
    return nil
  end

  local base_indent_len = #item.indent
  local last = lnum
  local i = lnum + 1
  while lines[i] and lines[i] ~= '' and #(lines[i]:match('^(%s*)')) > base_indent_len do
    last = i
    i = i + 1
  end

  local updated = {}
  for j = lnum, last do
    local line = lines[j]
    if direction > 0 then
      updated[#updated + 1] = '  ' .. line
    else
      updated[#updated + 1] = (line:gsub('^%s%s?', '', 1))
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, last, false, updated)
  return last - lnum + 1
end

function M.indent_item(bufnr, lnum)
  return M.shift_item(bufnr, lnum, 1)
end

function M.outdent_item(bufnr, lnum)
  return M.shift_item(bufnr, lnum, -1)
end

--- Continue the list at the cursor (real org-mode's Enter-in-a-list
--- behavior): splits the current line at `col` like a normal newline,
--- but prefixes the new line with the same bullet (or the next number,
--- for an ordered item — renumbering the rest of the run to match) and
--- indent. A checkbox item continues with a fresh, unchecked `[ ]`.
--- Pressing Enter on an *empty* item (no text after the bullet/checkbox)
--- exits the list instead: the bullet is removed, leaving a blank line.
--- Returns true if it handled the line (a list item), false otherwise —
--- callers should fall back to a plain newline on false.
function M.continue_at_cursor(bufnr, win, lnum, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local item = M.parse(line)
  if not item then
    return false
  end

  local content_without_checkbox = item.content:gsub('^%[[ xX]%]%s*', '')
  if content_without_checkbox:match('^%s*$') then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { '' })
    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
    return true
  end

  local before = line:sub(1, col)
  local after = line:sub(col + 1)

  local new_item = vim.deepcopy(item)
  if item.kind == 'ordered' then
    new_item.number = item.number + 1
  end
  local marker = render_marker(new_item)
  if checkbox_mod.is_checkbox(render_marker(item) .. item.content) then
    marker = marker .. '[ ] '
  end

  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { before, marker .. after })
  vim.api.nvim_win_set_cursor(win, { lnum + 1, #marker })
  if item.kind == 'ordered' then
    M.renumber(bufnr, lnum + 1)
  end
  return true
end

return M

--- Statistics cookies: the `[2/5]` / `[40%]` markers org lets you put in
--- a headline's title, kept in sync with either the checkboxes or the
--- direct child headlines underneath it.
local headline_mod = require('mep.org.headline')
local checkbox_mod = require('mep.org.checkbox')
local outline = require('mep.org.outline')

local M = {}

--- Find a `[n/m]` or `[n%]` (or empty `[/]` / `[%]`) statistics cookie in
--- `title`. Returns `start_col, end_col, kind` (1-based, inclusive;
--- kind is `'fraction'` or `'percent'`), or nil if there isn't one.
function M.find_cookie(title)
  local s, e = title:find('%[%d*/%d*%]')
  if s then
    return s, e, 'fraction'
  end
  s, e = title:find('%[%d*%%%]')
  if s then
    return s, e, 'percent'
  end
  return nil
end

--- Count checkbox items anywhere within the subtree rooted at `lnum`
--- (not the headline line itself). Returns `done, total`.
function M.count_checkboxes(bufnr, lnum)
  local last = outline.subtree_end(bufnr, lnum)
  if last < lnum + 1 then
    return 0, 0
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum, last, false) -- 1-based (lnum+1)..last
  local done, total = 0, 0
  for _, line in ipairs(lines) do
    local checked = checkbox_mod.is_checked(line)
    if checked ~= nil then
      total = total + 1
      if checked then
        done = done + 1
      end
    end
  end
  return done, total
end

--- Count *direct* child headlines (not deeper descendants) by TODO
--- state. A child counts as done if its keyword is the last entry of
--- `todo_keywords` (e.g. "DONE" in the default `{'TODO','DONE'}`);
--- anything else — including no keyword — counts as not done. Returns
--- `done, total`.
function M.count_child_todos(bufnr, lnum, todo_keywords)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local level = #(lines[lnum]:match('^(%*+)'))
  local last = outline.subtree_end(bufnr, lnum)
  local done_kw = todo_keywords and todo_keywords[#todo_keywords]

  local done, total = 0, 0
  local i = lnum + 1
  while i <= last do
    local line = lines[i]
    if headline_mod.is_headline(line) then
      local child_level = #(line:match('^(%*+)'))
      if child_level == level + 1 then
        total = total + 1
        local parsed = headline_mod.parse(line, todo_keywords or {})
        if parsed.todo == done_kw then
          done = done + 1
        end
        i = outline.subtree_end(bufnr, i) -- skip this child's own subtree
      end
    end
    i = i + 1
  end
  return done, total
end

--- Recompute and rewrite the statistics cookie in the headline at
--- `lnum`, if it has one. Prefers counting checkboxes anywhere in the
--- subtree; if there are none, falls back to direct child headlines'
--- TODO state. Returns `done, total`, or nil if there was no cookie to
--- update (a no-op in that case).
function M.update_cookie(bufnr, lnum, todo_keywords)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line or not headline_mod.is_headline(line) then
    return nil
  end
  local parsed = headline_mod.parse(line, todo_keywords or {})
  local s, e, kind = M.find_cookie(parsed.title)
  if not s then
    return nil
  end

  local done, total = M.count_checkboxes(bufnr, lnum)
  if total == 0 then
    done, total = M.count_child_todos(bufnr, lnum, todo_keywords)
  end

  local replacement
  if kind == 'percent' then
    local pct = total > 0 and math.floor((done / total) * 100 + 0.5) or 0
    replacement = '[' .. pct .. '%]'
  else
    replacement = '[' .. done .. '/' .. total .. ']'
  end

  parsed.title = parsed.title:sub(1, s - 1) .. replacement .. parsed.title:sub(e + 1)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { headline_mod.render(parsed) })
  return done, total
end

--- Update the statistics cookie (if any) on the headline containing
--- `lnum`, and every ancestor headline above it that also has one — call
--- after a checkbox toggle or TODO-state change so cookies elsewhere in
--- the outline path stay in sync, not just the immediate parent.
function M.update_ancestors(bufnr, lnum, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  while at do
    M.update_cookie(bufnr, at, todo_keywords)
    at = outline.parent_headline(bufnr, at)
  end
end

return M

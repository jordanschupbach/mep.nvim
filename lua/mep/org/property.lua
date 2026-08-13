--- `:PROPERTIES: ... :END:` drawers: a key/value map per headline, sitting
--- right after the headline (and after its planning line, if any) and
--- before body text. Generalizes the narrow ad-hoc scanner
--- `mep.org.link` built for `id:`/`#custom-id` lookups back in Phase 5
--- — that module now delegates here instead of duplicating the logic.
local plan_mod = require('mep.org.plan')
local outline = require('mep.org.outline')

local M = {}

--- The properties-drawer line range for the headline at `headline_lnum`:
--- `start_lnum, end_lnum` (1-based, inclusive of the `:PROPERTIES:`/
--- `:END:` lines themselves), or nil if it has none.
function M.find(bufnr, headline_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local j = headline_lnum + 1
  if lines[j] and plan_mod.is_plan_line(lines[j]) then
    j = j + 1
  end
  if not (lines[j] and lines[j]:match('^%s*:PROPERTIES:%s*$')) then
    return nil
  end
  local start = j
  local k = j + 1
  while lines[k] and not lines[k]:match('^%s*:END:%s*$') do
    k = k + 1
  end
  if lines[k] then
    return start, k
  end
  return nil
end

--- Parse the headline at `headline_lnum`'s own properties drawer.
--- Returns an ordered list of `{ key, value }` (preserving original
--- order/casing and any duplicate keys as separate entries) and a
--- `by_key` lookup table (key upper-cased, last entry wins on
--- duplicates — matching real org-mode). Both are `{}` if there's no
--- drawer.
function M.parse(bufnr, headline_lnum)
  local start, stop = M.find(bufnr, headline_lnum)
  local list, by_key = {}, {}
  if not start then
    return list, by_key
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start, stop - 1, false)
  for _, line in ipairs(lines) do
    local k, v = line:match('^%s*:([%w_%-]+):%s*(.-)%s*$')
    if k then
      list[#list + 1] = { key = k, value = v }
      by_key[k:upper()] = v
    end
  end
  return list, by_key
end

--- The value of property `key` (case-insensitive) on the headline
--- containing `lnum`'s own drawer — not inherited, not a search. nil if
--- absent or `lnum` isn't inside a headline.
function M.get(bufnr, lnum, key)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local _, by_key = M.parse(bufnr, at)
  return by_key[key:upper()]
end

--- The line number of the first headline in `bufnr` whose own `key`
--- property equals `value` (case-insensitive key, exact-match value), or
--- nil.
function M.find_by(bufnr, key, value)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match('^%*+%s') and M.get(bufnr, i, key) == value then
      return i
    end
  end
  return nil
end

--- Rewrite the headline at `lnum`'s properties drawer to contain exactly
--- `list` (a list of `{ key, value }`, as from `parse`'s first return),
--- creating the drawer (right after the headline/planning line) if it
--- doesn't exist yet, or removing it entirely if `list` is empty.
function M.write(bufnr, lnum, list)
  local start, stop = M.find(bufnr, lnum)
  local rendered = {}
  if #list > 0 then
    rendered[1] = ':PROPERTIES:'
    for _, entry in ipairs(list) do
      rendered[#rendered + 1] = ':' .. entry.key .. ': ' .. entry.value
    end
    rendered[#rendered + 1] = ':END:'
  end

  if start then
    vim.api.nvim_buf_set_lines(bufnr, start - 1, stop, false, rendered)
  elseif #rendered > 0 then
    local insert_at = lnum
    local next_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
    if next_line and plan_mod.is_plan_line(next_line) then
      insert_at = lnum + 1
    end
    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, rendered)
  end
end

--- Set property `key` to `value` on the headline containing `lnum`,
--- creating the drawer if needed or updating the existing entry
--- (matched case-insensitively; a pre-existing duplicate collapses to
--- one entry). Returns `value`, or nil if `lnum` isn't inside a
--- headline.
function M.set(bufnr, lnum, key, value)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local list = M.parse(bufnr, at)
  local found = false
  for _, entry in ipairs(list) do
    if entry.key:upper() == key:upper() then
      entry.value = value
      found = true
    end
  end
  if not found then
    list[#list + 1] = { key = key, value = value }
  end
  M.write(bufnr, at, list)
  return value
end

--- Remove property `key` from the headline containing `lnum`'s drawer
--- (deleting the drawer entirely if nothing is left in it). Returns
--- true if it was present, false if not, nil if `lnum` isn't inside a
--- headline.
function M.remove(bufnr, lnum, key)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local list = M.parse(bufnr, at)
  local new_list, removed = {}, false
  for _, entry in ipairs(list) do
    if entry.key:upper() == key:upper() then
      removed = true
    else
      new_list[#new_list + 1] = entry
    end
  end
  M.write(bufnr, at, new_list)
  return removed
end

--- Interactively set a property on the headline containing `lnum`,
--- prompting for key then value via `vim.ui.input` (real org-mode's
--- `org-set-property`, `C-c C-x p`).
function M.set_interactive(bufnr, lnum)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return
  end
  vim.ui.input({ prompt = 'Property name: ' }, function(key)
    if not key or key == '' then
      return
    end
    vim.ui.input({ prompt = 'Property value: ' }, function(value)
      if not value then
        return
      end
      M.set(bufnr, at, key, value)
    end)
  end)
end

return M

--- Sort sibling headlines (same level, same parent), moving whole
--- subtrees together so nested content follows its heading.
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')

local M = {}

--- Built-in sort key functions: given a parsed headline (see
--- headline.parse) and the configured todo_keywords list, return a
--- comparable sort key (string or number, consistently for one call).
M.criteria = {
  alpha = function(parsed)
    return (parsed.title or ''):lower()
  end,
  -- Keyword position in todo_keywords (1-based); a headline with no
  -- keyword at all sorts after every configured keyword — it's read as
  -- "not tracked as a task", not as "earliest in the sequence".
  todo = function(parsed, todo_keywords)
    todo_keywords = todo_keywords or {}
    if parsed.todo then
      for i, kw in ipairs(todo_keywords) do
        if kw == parsed.todo then
          return i
        end
      end
    end
    return #todo_keywords + 1
  end,
  -- Priority letters already sort correctly as plain strings ('A' < 'B'
  -- < 'C'); a headline with no priority cookie sorts after every lettered
  -- one ('~' is greater than any uppercase letter in byte order).
  priority = function(parsed)
    return parsed.priority or '~'
  end,
}

--- Sort the sibling headlines around `lnum` — its siblings under the
--- same parent, or every top-level headline if `lnum` has no parent —
--- by `criteria` (a key into `M.criteria`, or a
--- `function(parsed, todo_keywords) -> comparable`). `reverse` (optional)
--- sorts descending. Returns the number of siblings sorted, or nil if
--- `lnum` isn't inside any headline. Ties may reorder relative to each
--- other (Lua's table.sort isn't stable).
function M.sort_siblings(bufnr, lnum, criteria, todo_keywords, reverse)
  local key_fn = type(criteria) == 'function' and criteria or M.criteria[criteria]
  assert(key_fn, 'mep.org.sort: unknown criteria "' .. tostring(criteria) .. '"')

  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end

  local lines_all = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local level = #(lines_all[at]:match('^(%*+)'))
  local parent = outline.parent_headline(bufnr, at)

  local scan_start, scan_end
  if parent then
    scan_start, scan_end = parent + 1, outline.subtree_end(bufnr, parent)
  else
    scan_start, scan_end = 1, #lines_all
  end

  local siblings = {}
  local i = scan_start
  while i <= scan_end do
    local line = lines_all[i]
    if line:match('^%*+%s') and #(line:match('^(%*+)')) == level then
      local sib_end = outline.subtree_end(bufnr, i)
      siblings[#siblings + 1] = { start = i, stop = sib_end }
      i = sib_end + 1
    else
      i = i + 1
    end
  end

  if #siblings <= 1 then
    return #siblings
  end

  local first, last = siblings[1].start, siblings[#siblings].stop
  local blocks = {}
  for _, sib in ipairs(siblings) do
    local block_lines = vim.api.nvim_buf_get_lines(bufnr, sib.start - 1, sib.stop, false)
    local parsed = headline_mod.parse(block_lines[1], todo_keywords or {})
    blocks[#blocks + 1] = { lines = block_lines, key = key_fn(parsed, todo_keywords) }
  end

  table.sort(blocks, function(a, b)
    if reverse then
      return a.key > b.key
    end
    return a.key < b.key
  end)

  local combined = {}
  for _, b in ipairs(blocks) do
    vim.list_extend(combined, b.lines)
  end
  vim.api.nvim_buf_set_lines(bufnr, first - 1, last, false, combined)

  return #siblings
end

return M

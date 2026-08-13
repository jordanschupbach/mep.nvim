--- Priority cookies: the `[#A]`/`[#B]`/`[#C]` marker org lets you put
--- right after a headline's (optional) TODO keyword. Real org-mode's
--- `org-priority` is prompt-based (`C-c ,`); this instead cycles through
--- a configured list — simpler, and consistent with mep.org.todo's own
--- cycle-based approach rather than a blocking prompt.
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')

local M = {}

--- Set (or, with `priority = nil`, clear) the priority cookie on the
--- headline containing `lnum`. Returns `priority`, or nil if `lnum`
--- isn't inside a headline.
function M.set(bufnr, lnum, priority, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})
  parsed.priority = priority
  vim.api.nvim_buf_set_lines(bufnr, at - 1, at, false, { headline_mod.render(parsed) })
  return priority
end

--- Cycle the priority cookie on the headline containing `lnum` through
--- `priorities` (default `{'A', 'B', 'C'}`), then to no priority, then
--- back to the first. Returns the new priority (a letter, or nil for "no
--- priority"), or nil if `lnum` isn't inside a headline (ambiguous with
--- "cycled to no priority" — check `outline.current_headline` first if
--- that distinction matters).
function M.cycle(bufnr, lnum, priorities, todo_keywords)
  priorities = priorities or { 'A', 'B', 'C' }
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})

  local next_index = 1
  if parsed.priority then
    for i, p in ipairs(priorities) do
      if p == parsed.priority then
        next_index = i + 1
        break
      end
    end
  end

  parsed.priority = priorities[next_index] -- nil past the end: "no priority"
  vim.api.nvim_buf_set_lines(bufnr, at - 1, at, false, { headline_mod.render(parsed) })
  return parsed.priority
end

return M

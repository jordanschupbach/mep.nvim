local headline = require('mep.org.headline')

local M = {}

--- Cycle the TODO state of the headline at `lnum` in `bufnr` through
--- `todo_keywords`, then to no keyword, then back to the first keyword.
--- Rewrites the line. Returns the new state (a keyword string, or nil
--- for "no keyword"), or nil if `lnum` isn't a headline.
function M.cycle(bufnr, lnum, todo_keywords)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then
    return nil
  end
  local parsed = headline.parse(line, todo_keywords)
  if not parsed then
    return nil
  end

  local next_index = 1
  if parsed.todo then
    for i, kw in ipairs(todo_keywords) do
      if kw == parsed.todo then
        next_index = i + 1
        break
      end
    end
  end

  parsed.todo = todo_keywords[next_index] -- nil past the end: "no keyword"
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { headline.render(parsed) })
  return parsed.todo
end

return M

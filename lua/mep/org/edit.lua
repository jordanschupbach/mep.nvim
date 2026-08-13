--- Headline insertion ("M-RET"/"M-S-RET" equivalents). Pure line-pattern
--- operations, same as the rest of mep.org's structural pieces — no
--- tree-sitter parser needed.
local headline = require('mep.org.headline')
local outline = require('mep.org.outline')

local M = {}

--- Insert a new, empty headline as the next sibling of the headline
--- containing `lnum` — same level, placed after the current subtree's
--- content so any nested children aren't disrupted. `opts.todo`
--- (optional) pre-fills a TODO keyword. Returns the new headline's line
--- number (with the buffer left ready for the title to be typed right
--- after the trailing space), or nil if `lnum` isn't inside any
--- headline.
function M.insert_headline(bufnr, lnum, opts)
  opts = opts or {}
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end

  local current_line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local level = #(current_line:match('^(%*+)'))
  local insert_at = outline.subtree_end(bufnr, at)

  local new_line = headline.render({ level = level, todo = opts.todo, title = '', tags = {} })
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { new_line })

  return insert_at + 1
end

--- Like `insert_headline`, but pre-fills the first of `todo_keywords` as
--- the new headline's TODO state.
function M.insert_todo_headline(bufnr, lnum, todo_keywords)
  return M.insert_headline(bufnr, lnum, { todo = todo_keywords and todo_keywords[1] })
end

return M

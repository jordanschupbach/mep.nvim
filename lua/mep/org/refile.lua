--- Move a subtree to become the last child of another headline — in the
--- current buffer for now (see ORGMODE_ROADMAP.md phase 9/agenda for
--- when cross-file refiling becomes relevant). Target selection goes
--- through `mep.picker`, the same general-purpose picker engine used
--- for find_files/live_grep/buffer_search.
local outline = require('mep.org.outline')
local headline_mod = require('mep.org.headline')

local M = {}

--- Every headline in `bufnr`, each with a "/"-joined breadcrumb of
--- ancestor titles down to (and including) itself. Returns a list of
--- `{ lnum, level, display }`.
function M.targets(bufnr, todo_keywords)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stack = {} -- level -> title, built up as we scan down the buffer
  local out = {}
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      local parsed = headline_mod.parse(line, todo_keywords or {})
      stack[parsed.level] = parsed.title
      for lvl in pairs(stack) do
        if lvl > parsed.level then
          stack[lvl] = nil
        end
      end
      local crumbs = {}
      for lvl = 1, parsed.level do
        crumbs[#crumbs + 1] = stack[lvl] or ''
      end
      out[#out + 1] = { lnum = i, level = parsed.level, display = table.concat(crumbs, ' / ') }
    end
  end
  return out
end

--- Move the subtree at `from_lnum` to become the last child of the
--- headline at `target_lnum` (both in `bufnr`), promoting/demoting it to
--- fit one level deeper than the target. Returns the moved subtree's new
--- starting line, or nil if either isn't a headline, or the target is
--- inside the subtree being moved.
function M.refile(bufnr, from_lnum, target_lnum)
  local from_at = outline.current_headline(bufnr, from_lnum)
  local target_at = outline.current_headline(bufnr, target_lnum)
  if not from_at or not target_at then
    return nil
  end
  local from_stop = outline.subtree_end(bufnr, from_at)
  if target_at >= from_at and target_at <= from_stop then
    return nil -- can't refile into your own subtree
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local from_level = #(lines[from_at]:match('^(%*+)'))
  local target_level = #(lines[target_at]:match('^(%*+)'))
  local delta = (target_level + 1) - from_level

  local block = vim.api.nvim_buf_get_lines(bufnr, from_at - 1, from_stop, false)
  local adjusted = {}
  for _, line in ipairs(block) do
    if headline_mod.is_headline(line) then
      local stars, rest = line:match('^(%*+)(.*)$')
      adjusted[#adjusted + 1] = string.rep('*', math.max(1, #stars + delta)) .. rest
    else
      adjusted[#adjusted + 1] = line
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, from_at - 1, from_stop, false, {})

  -- line numbers below the removed block shifted up; adjust if the
  -- target was after the source
  local target_at_after = target_at
  if from_at < target_at then
    target_at_after = target_at - (from_stop - from_at + 1)
  end
  local insert_at = outline.subtree_end(bufnr, target_at_after)

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, adjusted)
  return insert_at + 1
end

--- Open a `mep.picker` over every valid refile target in `bufnr` (every
--- headline except the subtree at `from_lnum` and its own descendants)
--- and refile there on selection.
function M.refile_interactive(bufnr, from_lnum, todo_keywords)
  local from_at = outline.current_headline(bufnr, from_lnum)
  local from_stop = from_at and outline.subtree_end(bufnr, from_at)

  local items = {}
  for _, t in ipairs(M.targets(bufnr, todo_keywords)) do
    if not (from_at and t.lnum >= from_at and t.lnum <= from_stop) then
      items[#items + 1] = t
    end
  end

  require('mep.picker').start({
    prompt_title = 'Refile to',
    items = items,
    entry_to_string = function(item)
      return item.display
    end,
    on_select = function(item)
      M.refile(bufnr, from_lnum, item.lnum)
    end,
  })
end

return M

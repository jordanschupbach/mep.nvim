--- Headline outline navigation and promote/demote, all 1-based buffer
--- line numbers, all pure line-pattern matching (see headline.lua).
local headline = require('mep.org.headline')

local M = {}

local function buf_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function star_level(line)
  local stars = line:match('^(%*+)')
  return stars and #stars or nil
end

--- The next headline strictly after `lnum`, or nil. `max_level`
--- (optional) restricts to headlines at that level or shallower.
function M.next_headline(bufnr, lnum, max_level)
  local lines = buf_lines(bufnr)
  for i = lnum + 1, #lines do
    if headline.is_headline(lines[i]) then
      if not max_level or star_level(lines[i]) <= max_level then
        return i
      end
    end
  end
  return nil
end

--- The previous headline strictly before `lnum`, or nil.
function M.prev_headline(bufnr, lnum, max_level)
  local lines = buf_lines(bufnr)
  for i = lnum - 1, 1, -1 do
    if headline.is_headline(lines[i]) then
      if not max_level or star_level(lines[i]) <= max_level then
        return i
      end
    end
  end
  return nil
end

--- The headline `lnum` belongs to (itself, if it is one), or nil if
--- there's no headline at or above it.
function M.current_headline(bufnr, lnum)
  local lines = buf_lines(bufnr)
  for i = lnum, 1, -1 do
    if headline.is_headline(lines[i]) then
      return i
    end
  end
  return nil
end

--- The parent headline of `lnum` (nearest headline above it with a
--- strictly lower level), or nil at the top level / with no headline.
function M.parent_headline(bufnr, lnum)
  local lines = buf_lines(bufnr)
  local at = M.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local level = star_level(lines[at])
  for i = at - 1, 1, -1 do
    if headline.is_headline(lines[i]) and star_level(lines[i]) < level then
      return i
    end
  end
  return nil
end

--- The last line of the subtree rooted at the headline on `lnum` (up to
--- but not including the next headline at the same level or shallower).
function M.subtree_end(bufnr, lnum)
  local lines = buf_lines(bufnr)
  local level = star_level(lines[lnum])
  if not level then
    return lnum
  end
  for i = lnum + 1, #lines do
    if headline.is_headline(lines[i]) and star_level(lines[i]) <= level then
      return i - 1
    end
  end
  return #lines
end

--- Change the level of the headline on `lnum` by `delta` stars (+1 =
--- demote, -1 = promote), clamped to a minimum of 1. Only the headline
--- itself is changed, not its subtree (matching Emacs org-mode's plain
--- M-Left/M-Right, as opposed to the subtree-wide variant). Returns the
--- new level, or nil if `lnum` isn't a headline.
function M.change_level(bufnr, lnum, delta)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line or not headline.is_headline(line) then
    return nil
  end
  local stars, rest = line:match('^(%*+)(.*)$')
  local new_level = math.max(1, #stars + delta)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { string.rep('*', new_level) .. rest })
  return new_level
end

--- Like `change_level`, but applies `delta` to every headline in the
--- subtree rooted at `lnum` (preserving their levels relative to each
--- other), clamped so the root headline never drops below 1 star — since
--- the root always has the shallowest level in its own subtree, that
--- single clamp keeps every descendant valid too. Returns the root's new
--- level, or nil if `lnum` isn't a headline.
function M.change_level_subtree(bufnr, lnum, delta)
  local lines = buf_lines(bufnr)
  local root_level = star_level(lines[lnum])
  if not root_level then
    return nil
  end
  if root_level + delta < 1 then
    delta = 1 - root_level
  end

  local last = M.subtree_end(bufnr, lnum)
  local updated = {}
  for i = lnum, last do
    local line = lines[i]
    if headline.is_headline(line) then
      local stars, rest = line:match('^(%*+)(.*)$')
      updated[#updated + 1] = string.rep('*', #stars + delta) .. rest
    else
      updated[#updated + 1] = line
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, last, false, updated)
  return root_level + delta
end

--- Swap the subtree rooted at `lnum` with its previous (`direction =
--- -1`) or next (`direction = 1`) sibling subtree (same level, same
--- parent). Returns the moved subtree's new starting line number, or nil
--- if there's no such sibling (already first/last, or `lnum` isn't a
--- headline).
function M.move_subtree(bufnr, lnum, direction)
  local lines = buf_lines(bufnr)
  local level = star_level(lines[lnum])
  if not level then
    return nil
  end
  local this_start, this_end = lnum, M.subtree_end(bufnr, lnum)

  if direction < 0 then
    local prev_start = nil
    for i = this_start - 1, 1, -1 do
      if headline.is_headline(lines[i]) then
        local lvl = star_level(lines[i])
        if lvl < level then
          break -- hit the parent (or shallower): no previous sibling
        elseif lvl == level then
          prev_start = i
          break
        end
      end
    end
    if not prev_start then
      return nil
    end

    local block_prev = vim.api.nvim_buf_get_lines(bufnr, prev_start - 1, this_start - 1, false)
    local block_this = vim.api.nvim_buf_get_lines(bufnr, this_start - 1, this_end, false)
    local combined = {}
    vim.list_extend(combined, block_this)
    vim.list_extend(combined, block_prev)
    vim.api.nvim_buf_set_lines(bufnr, prev_start - 1, this_end, false, combined)
    return prev_start
  else
    local next_start = this_end + 1
    if next_start > #lines or not headline.is_headline(lines[next_start]) or star_level(lines[next_start]) ~= level then
      return nil
    end
    local next_end = M.subtree_end(bufnr, next_start)

    local block_this = vim.api.nvim_buf_get_lines(bufnr, this_start - 1, this_end, false)
    local block_next = vim.api.nvim_buf_get_lines(bufnr, next_start - 1, next_end, false)
    local combined = {}
    vim.list_extend(combined, block_next)
    vim.list_extend(combined, block_this)
    vim.api.nvim_buf_set_lines(bufnr, this_start - 1, next_end, false, combined)
    return this_start + #block_next
  end
end

return M

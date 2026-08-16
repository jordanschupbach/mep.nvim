--- A headline's own direct body text — the review UI's "answer",
--- revealed on demand. Everything between the headline's own planning
--- line/properties drawer and the next headline at *any* level (so a
--- child headline's own content is excluded — that's a separate card,
--- not part of this one's answer), leading/trailing blank lines
--- trimmed.
local property = require('mep.org.property')
local plan = require('mep.org.plan')
local outline = require('mep.org.outline')

local M = {}

--- The 1-based line the body actually starts at: right after the
--- headline, skipping its planning line and/or properties drawer if
--- either is present (in that order — real org-mode's own layout).
local function body_start(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local at = lnum + 1
  if lines[at] and plan.is_plan_line(lines[at]) then
    at = at + 1
  end
  local drawer_start, drawer_end = property.find(bufnr, lnum)
  if drawer_start and drawer_start >= lnum + 1 then
    at = drawer_end + 1
  end
  return at
end

--- `bufnr`'s headline at `lnum`'s own body text, as a list of lines
--- (`{}` if it has none).
function M.answer_text(bufnr, lnum)
  local start = body_start(bufnr, lnum)
  local stop = (outline.next_headline(bufnr, lnum) or (vim.api.nvim_buf_line_count(bufnr) + 1)) - 1
  if stop < start then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start - 1, stop, false)

  local first, last = 1, #lines
  while first <= last and lines[first]:match('^%s*$') do
    first = first + 1
  end
  while last >= first and lines[last]:match('^%s*$') do
    last = last - 1
  end
  local trimmed = {}
  for i = first, last do
    trimmed[#trimmed + 1] = lines[i]
  end
  return trimmed
end

return M

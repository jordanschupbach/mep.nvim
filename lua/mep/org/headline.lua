--- Pure line-oriented parsing of org headlines ("* TODO Title :tag1:tag2:")
--- — no treesitter dependency, so outline navigation, TODO cycling,
--- checkbox toggling, and folding all work even before (or without) the
--- `org` tree-sitter parser being installed. Only syntax *highlighting*
--- (mep.org.org, via mep.treesitter) needs the parser.
local M = {}

--- Whether `line` is an org headline at all (fast path; use `parse` to
--- get its parts).
function M.is_headline(line)
  return line:match('^%*+%s') ~= nil
end

--- Parse a headline line into `{ level, todo, priority, title, tags }`,
--- or nil if `line` isn't a headline. `todo_keywords` (e.g. `{ 'TODO',
--- 'DONE' }`) controls which leading word counts as a TODO state rather
--- than part of the title. A `[#A]`-style priority cookie (single
--- alphanumeric character, immediately after the TODO keyword if any) is
--- recognized regardless of `todo_keywords`, matching real org-mode.
function M.parse(line, todo_keywords)
  local stars, rest = line:match('^(%*+)%s+(.*)$')
  if not stars then
    return nil
  end

  local todo = nil
  for _, kw in ipairs(todo_keywords or {}) do
    if rest == kw or rest:sub(1, #kw + 1) == kw .. ' ' then
      todo = kw
      rest = rest:sub(#kw + 1):gsub('^%s+', '')
      break
    end
  end

  local priority = rest:match('^%[#(%w)%]')
  if priority then
    rest = rest:gsub('^%[#%w%]%s*', '')
  end

  local title, tags_str = rest:match('^(.-)%s*:([%w_%-:]+):%s*$')
  local tags = {}
  if tags_str then
    for tag in tags_str:gmatch('[^:]+') do
      tags[#tags + 1] = tag
    end
  else
    title = rest
  end

  return { level = #stars, todo = todo, priority = priority, title = title, tags = tags }
end

--- Rebuild a headline line from parts as returned by `parse` (round-trips
--- modulo exact original whitespace between title and tags).
function M.render(headline)
  local parts = { string.rep('*', headline.level) }
  if headline.todo then
    parts[#parts + 1] = headline.todo
  end
  if headline.priority then
    parts[#parts + 1] = '[#' .. headline.priority .. ']'
  end
  parts[#parts + 1] = headline.title
  local line = table.concat(parts, ' ')
  if headline.tags and #headline.tags > 0 then
    line = line .. '  :' .. table.concat(headline.tags, ':') .. ':'
  end
  return line
end

return M

--- Zero-dependency fuzzy matcher. Subsequence matching (like fzf/telescope's
--- default sorter) with bonuses for consecutive characters and matches at
--- word boundaries, and a penalty for loosely-spread matches.
local M = {}

--- Fuzzy-match `query` against `str`. Returns `score, positions` (1-based
--- byte offsets into `str` for highlighting) on success, or `nil` if `str`
--- doesn't contain `query` as a subsequence. Case-insensitive unless
--- `query` contains an uppercase letter (smart case).
function M.match(str, query)
  if query == '' then
    return 0, {}
  end

  local smart_case = query:match('%u') == nil
  local hay = smart_case and str:lower() or str
  local needle = smart_case and query:lower() or query

  local positions = {}
  local search_from = 1
  local score = 0
  local consecutive = 0
  local prev_pos = nil

  for i = 1, #needle do
    local ch = needle:sub(i, i)
    local found = hay:find(ch, search_from, true)
    if not found then
      return nil
    end

    if prev_pos and found == prev_pos + 1 then
      consecutive = consecutive + 1
      score = score + 15 + consecutive * 5
    else
      consecutive = 0
      score = score + 1
    end

    if found == 1 then
      score = score + 10
    else
      local prev_char = str:sub(found - 1, found - 1)
      if prev_char:match('[%s%-_/%.]') then
        score = score + 10
      end
    end

    positions[#positions + 1] = found
    prev_pos = found
    search_from = found + 1
  end

  local span = positions[#positions] - positions[1] + 1
  score = score - (span - #needle)
  score = score - #str * 0.01

  return score, positions
end

--- Filter+sort `items` (any list) against `query`, using
--- `entry_to_string(item)` to get the text each item is matched against.
--- Returns a list of `{ item, score, positions, text }`, best matches first.
function M.filter(items, query, entry_to_string)
  local results = {}
  for _, item in ipairs(items) do
    local str = entry_to_string(item)
    local score, positions = M.match(str, query)
    if score then
      results[#results + 1] = { item = item, score = score, positions = positions, text = str }
    end
  end
  table.sort(results, function(a, b)
    return a.score > b.score
  end)
  return results
end

return M

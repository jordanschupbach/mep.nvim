--- Minimal BibTeX parser: `@type{key, field = {value}, field2 = "v2",
--- field3 = 2023, ...}` into `{ key, type, fields = { field = value,
--- ... } }` entries. Pure line/brace-scanning, no external dependency —
--- not a full BibTeX grammar (no `@string`/`@comment` macro expansion,
--- no escaped-brace edge cases inside a value); handles the common case
--- real-world `.bib` files overwhelmingly are.
local M = {}

--- Split `s` on commas that sit outside any `{...}`/`"..."` nesting
--- (so a value like `{Some, Title}` or `"a, b"` doesn't get split
--- apart), trimming surrounding whitespace off each piece.
local function split_top_level(s)
  local parts = {}
  local buf = {}
  local depth = 0
  local in_quotes = false
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '"' then
      in_quotes = not in_quotes
      buf[#buf + 1] = c
    elseif c == '{' and not in_quotes then
      depth = depth + 1
      buf[#buf + 1] = c
    elseif c == '}' and not in_quotes then
      depth = depth - 1
      buf[#buf + 1] = c
    elseif c == ',' and depth == 0 and not in_quotes then
      parts[#parts + 1] = table.concat(buf)
      buf = {}
    else
      buf[#buf + 1] = c
    end
    i = i + 1
  end
  local tail = table.concat(buf)
  if tail:match('%S') then
    parts[#parts + 1] = tail
  end
  for idx, p in ipairs(parts) do
    parts[idx] = p:match('^%s*(.-)%s*$')
  end
  return parts
end

--- Strip one level of `{...}`/`"..."` delimiters off a field value, or
--- pass a bare (unquoted, e.g. `year = 2023`) value through unchanged.
local function unwrap_value(v)
  if v:sub(1, 1) == '{' and v:sub(-1) == '}' then
    return v:sub(2, -2)
  end
  if v:sub(1, 1) == '"' and v:sub(-1) == '"' then
    return v:sub(2, -2)
  end
  return v
end

--- The `{...}` matching the opening brace at `start` (its own index) in
--- `s`, by brace-depth counting (so nested `{...}` inside a field value
--- doesn't end the entry early) — the entry's own closing-brace index,
--- or nil if unbalanced/unterminated.
local function matching_brace(s, start)
  local depth = 0
  local i, n = start, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '{' then
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
    i = i + 1
  end
  return nil
end

--- Parse `text` (a whole `.bib` file's content) into a list of `{ key,
--- type, fields = { [lowercased field name] = value } }` entries, in
--- file order.
function M.parse(text)
  local entries = {}
  local i, n = 1, #text
  while i <= n do
    local at = text:find('@', i, true)
    if not at then
      break
    end
    local brace = text:find('{', at + 1)
    if not brace then
      break
    end
    local etype = text:sub(at + 1, brace - 1):match('^%s*(%S+)%s*$')
    local close = matching_brace(text, brace)
    if not close then
      break
    end
    local body = text:sub(brace + 1, close - 1)
    local parts = split_top_level(body)
    if etype and parts[1] then
      local key = parts[1]
      local fields = {}
      for idx = 2, #parts do
        local name, value = parts[idx]:match('^([%w%-_]+)%s*=%s*(.*)$')
        if name then
          fields[name:lower()] = unwrap_value(value)
        end
      end
      entries[#entries + 1] = { key = key, type = etype:lower(), fields = fields }
    end
    i = close + 1
  end
  return entries
end

return M

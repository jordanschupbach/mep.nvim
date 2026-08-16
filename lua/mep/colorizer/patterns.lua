--- Pure line-pattern color detection: `#rgb`/`#rrggbb`/`#rrggbbaa`,
--- `rgb()`/`rgba()`, and CSS named colors (`mep.colorizer.names`).
--- Every `find_*` returns `start_col, end_col` (1-based, inclusive —
--- `mep.url.find`'s own convention) and a normalized lower-case
--- `#rrggbb` hex string, or nil if there's no match at/after `init`.
--- Alpha (an `#rrggbbaa` hex color's trailing byte, or `rgba()`'s 4th
--- argument) is consumed as part of the match span but dropped from the
--- returned color — this module surfaces color only, not transparency.
local names = require('mep.colorizer.names')

local M = {}

--- `digits` (a hex run of length 3/4/6/8, already validated by the
--- caller) to a plain `#rrggbb`: a 3/4-digit shorthand doubles each
--- digit (CSS's own shorthand rule — `#f00` == `#ff0000`), a 6/8-digit
--- one keeps just its first 6 (dropping any alpha pair).
local function normalize_hex(digits)
  digits = digits:lower()
  if #digits == 3 or #digits == 4 then
    local r, g, b = digits:sub(1, 1), digits:sub(2, 2), digits:sub(3, 3)
    return '#' .. r .. r .. g .. g .. b .. b
  end
  return '#' .. digits:sub(1, 6)
end

--- `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`. A `#`-prefixed hex run whose
--- length isn't exactly 3, 4, 6, or 8 isn't a valid CSS color at all
--- (matching real CSS's own token grammar — not a truncated prefix
--- match), so it's skipped rather than partially matched.
function M.find_hex(line, init)
  local pos = init or 1
  while true do
    local hash = line:find('#', pos, true)
    if not hash then
      return nil
    end
    local digits = line:match('^%x+', hash + 1)
    local len = digits and #digits or 0
    if len == 3 or len == 4 or len == 6 or len == 8 then
      return hash, hash + len, normalize_hex(digits:sub(1, len))
    end
    pos = hash + 1
  end
end

--- `rgb(r, g, b)` / `rgba(r, g, b, a)`, whitespace around each comma
--- tolerated. Each of r/g/b must be `0-255` (out-of-range values aren't
--- a valid CSS color; skipped rather than clamped, so a plain 3-number
--- tuple that isn't actually a color — e.g. some unrelated function
--- call named `rgb(...)` — doesn't get miscolored).
function M.find_rgb(line, init)
  local pos = init or 1
  while true do
    local s, e = line:find('rgba?%s*%(', pos)
    if not s then
      return nil
    end
    local close = line:find('%)', e + 1)
    if not close then
      return nil
    end
    local inner = line:sub(e + 1, close - 1)
    local r, g, b = inner:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
    if r then
      r, g, b = tonumber(r), tonumber(g), tonumber(b)
      if r <= 255 and g <= 255 and b <= 255 then
        return s, close, string.format('#%02x%02x%02x', r, g, b)
      end
    end
    pos = e + 1
  end
end

local function is_word_char(c)
  return c ~= nil and c:match('[%w_]') ~= nil
end

--- A CSS named color (`mep.colorizer.names.registry`, case-insensitive),
--- not immediately preceded/followed by another word character or
--- underscore — so `red` inside `background: red;` matches but the one
--- inside an identifier like `red_value`/`xred`/`red2` doesn't.
function M.find_named(line, init)
  local pos = init or 1
  while true do
    local s, e = line:find('%a+', pos)
    if not s then
      return nil
    end
    local hex = names.registry[line:sub(s, e):lower()]
    local before = s > 1 and line:sub(s - 1, s - 1) or nil
    local after = e < #line and line:sub(e + 1, e + 1) or nil
    if hex and not is_word_char(before) and not is_word_char(after) then
      return s, e, hex
    end
    pos = e + 1
  end
end

--- Every color match in `line`, left to right, non-overlapping (the
--- earliest-starting match among the three kinds wins at each position,
--- and the scan resumes right after it) — a list of `{ start_col,
--- end_col, hex }` (`mep.colorizer.patterns`'s own 1-based inclusive
--- convention).
function M.find_all(line)
  local results = {}
  local pos = 1
  while pos <= #line + 1 do
    local hs, he, hhex = M.find_hex(line, pos)
    local rs, re, rhex = M.find_rgb(line, pos)
    local ns, ne, nhex = M.find_named(line, pos)

    local best_s, best_e, best_hex
    for _, cand in ipairs({ { hs, he, hhex }, { rs, re, rhex }, { ns, ne, nhex } }) do
      if cand[1] and (not best_s or cand[1] < best_s) then
        best_s, best_e, best_hex = cand[1], cand[2], cand[3]
      end
    end
    if not best_s then
      break
    end
    results[#results + 1] = { start_col = best_s, end_col = best_e, hex = best_hex }
    pos = best_e + 1
  end
  return results
end

return M

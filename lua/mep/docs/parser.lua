--- Fallback function-signature detection: a plain Lua-pattern scan of
--- one line, used only when no LSP client can answer `mep.docs.lsp`'s
--- signature-help request. Deliberately narrow — single-line signatures
--- only (a multi-line parameter list won't match), and parameters are
--- returned as their raw trimmed source text (e.g. `x: int = 0` stays
--- one string) rather than parsed further into name/type/default; good
--- enough for a skeleton the user immediately edits, not a real parser.
local M = {}

--- Each filetype's patterns are tried in order; the first one that
--- matches `line` wins. Every pattern must capture exactly `(name,
--- params)` — an empty-parameter capture (`()`) is normalized to `{}` by
--- `M.parse`, not left as `{ '' }`.
local PATTERNS = {
  python = { 'def%s+([%w_]+)%s*%(([^)]*)%)' },
  lua = {
    'function%s+([%w_.:]+)%s*%(([^)]*)%)',
    'local%s+function%s+([%w_]+)%s*%(([^)]*)%)',
  },
  -- Two separate patterns, not one with an optional receiver group: a
  -- single `[^()]*` class greedily backtracks character-by-character
  -- against the immediately-following `(name)` capture (both match the
  -- same letters), and Lua's leftmost-longest-then-backtrack search
  -- stops at the *first* length that lets the rest of the pattern
  -- succeed — which, confirmed empirically, is one character short of
  -- "consume nothing" for a plain (no-receiver) function, silently
  -- capturing the name's last letter as a false receiver instead of the
  -- name itself. Requiring a receiver's own literal parens removes the
  -- ambiguity: a receiverless line never matches the first pattern at
  -- all, so there's nothing to backtrack into.
  go = {
    'func%s+([%w_]+)%s*%(([^)]*)%)',
    'func%s*%(.-%)%s*([%w_]+)%s*%(([^)]*)%)',
  },
  rust = { 'fn%s+([%w_]+)%s*%(([^)]*)%)' },
  ruby = { 'def%s+([%w_?!]+)%s*%(?([^)]*)%)?' },
  javascript = {
    'function%s*%*?%s*([%w_$]+)%s*%(([^)]*)%)',
    '([%w_$]+)%s*%(([^)]*)%)%s*{',
  },
  c = { '([%w_:*&<>, ]-[%s%*])([%w_]+)%s*%(([^)]*)%)%s*{' },
  java = { '([%w_<>%[%], ]-[%s])([%w_]+)%s*%(([^)]*)%)%s*[{]?' },
}
PATTERNS.typescript = PATTERNS.javascript
PATTERNS.javascriptreact = PATTERNS.javascript
PATTERNS.typescriptreact = PATTERNS.javascript
PATTERNS.cpp = PATTERNS.c

--- Split a raw parameter-list string (already stripped of its
--- surrounding parens) into trimmed, non-empty parameter strings.
local function split_params(raw)
  local params = {}
  if raw:match('^%s*$') then
    return params
  end
  for part in (raw .. ','):gmatch('([^,]*),') do
    local trimmed = part:match('^%s*(.-)%s*$')
    if trimmed ~= '' then
      params[#params + 1] = trimmed
    end
  end
  return params
end

--- Try every curated pattern for `filetype` against `line` in order,
--- returning `name, params` (params a possibly-empty list) from the
--- first match, or `nil` if none matched (or `filetype` has no curated
--- patterns at all).
function M.parse(line, filetype)
  for _, pattern in ipairs(PATTERNS[filetype] or {}) do
    -- The c/java patterns above capture a leading return-type group
    -- too (3 captures: type, name, params) — every other pattern
    -- captures just (name, params). Try 3-capture first, fall back to
    -- 2-capture, since Lua's string.find/match doesn't vary capture
    -- count based on what a pattern "could" match.
    local a, b, c = line:match(pattern)
    if a and c then
      return b, split_params(c)
    elseif a and b then
      return a, split_params(b)
    end
  end
  return nil
end

return M

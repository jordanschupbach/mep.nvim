--- Visually conceals raw markdown link/emphasis syntax — `[text](url)`
--- shows only `text`, `**bold**`/`*italic*`/`__bold__`/`_italic_`/
--- `~~strike~~` show only their inner text — mirrors `mep.org.
--- linkconceal`'s own extmark-conceal technique, broadened to cover
--- emphasis too (real markdown renderers hide those markers as well,
--- unlike org's own `*bold*` which stays literal even when rendered —
--- see `mep.org.export.ascii`'s own header comment on that difference).
---
--- Pure line-pattern matching, not tree-sitter, deliberately: `mep.
--- markdown`'s checkbox/fold pieces are pure-pattern too, for the same
--- "works immediately, even before/without the markdown_inline parser
--- being installed" reasoning `mep.org`'s own structural modules
--- document (only syntax highlighting depends on treesitter there; same
--- split here). A known, deliberate simplification of full CommonMark
--- emphasis-flanking rules (delimiter runs, escaped `\*`, code spans,
--- nested emphasis aren't specially handled) — good enough for typical
--- prose, not a spec-accurate parser. Needs `'conceallevel'` >= 2 on the
--- window to actually take visual effect; `mep.markdown.markdown` sets
--- that (plus `'concealcursor'`) per-window when `conceal` is enabled.
local M = {}

local ns = vim.api.nvim_create_namespace('mep_markdown_conceal')

--- Clear every concealment extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- `[text](url)` (an optional `"title"` after the url is swallowed into
--- the concealed span too, same as the url itself). Returns `s, e,
--- text_s, text_e` (1-based inclusive: the whole match, and just the
--- visible `text` portion within it), or nil.
local function find_link(line, init)
  local s, e, text_s, _text, text_e = line:find('%[()([^%[%]]*)()%]%([^%(%)]*%)', init)
  if not s then
    return nil
  end
  return s, e, text_s, text_e - 1
end

--- One occurrence of `delim` (e.g. `'**'`) wrapping non-whitespace-
--- flanked content with no other `delim` character inside — CommonMark's
--- own flanking rule, approximated: the character right after the
--- opening delimiter and right before the closing one must both be
--- non-whitespace, and the opening delimiter isn't itself immediately
--- followed by another one (so scanning for a *single* `*` at the first
--- star of `**bold**` correctly defers to the double-star matcher
--- instead of misfiring there). Returns `s, e, text_s, text_e` (as
--- `find_link`), or nil.
local function find_wrapped(line, init, delim)
  local dlen = #delim
  local pos = init
  while true do
    local s = line:find(delim, pos, true)
    if not s then
      return nil
    end
    local text_s = s + dlen
    local first = line:sub(text_s, text_s)
    if first ~= '' and not first:match('%s') and first ~= delim:sub(1, 1) then
      local search_from = text_s
      while true do
        local close = line:find(delim, search_from, true)
        if not close then
          break
        end
        local before = line:sub(close - 1, close - 1)
        if before ~= '' and not before:match('%s') then
          return s, close + dlen - 1, text_s, close - 1
        end
        search_from = close + 1
      end
    end
    pos = s + 1
  end
end

-- Longer (2-character) delimiters tried before their single-character
-- prefix, so `**`/`__` win over `*`/`_` at the same position — see
-- find_wrapped's own header comment on why that ordering alone isn't
-- enough on its own without the "not immediately followed by another
-- delimiter char" guard there too (a single `*` scan starting exactly
-- on the first char of a `**` run still has to be skipped there).
local EMPHASIS_DELIMS = { '**', '__', '~~', '*', '_' }

local function find_emphasis(line, init)
  local best
  for _, delim in ipairs(EMPHASIS_DELIMS) do
    local s, e, text_s, text_e = find_wrapped(line, init, delim)
    if s and (not best or s < best[1]) then
      best = { s, e, text_s, text_e }
    end
  end
  if best then
    return best[1], best[2], best[3], best[4]
  end
  return nil
end

--- Recompute concealment extmarks for every link/emphasis span in
--- `bufnr`, replacing whatever was there before.
function M.apply(bufnr)
  M.clear(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local init = 1
    while true do
      local ls, le, lts, lte = find_link(line, init)
      local es, ee, ets, ete = find_emphasis(line, init)

      local s, e, text_s, text_e
      if ls and (not es or ls <= es) then
        s, e, text_s, text_e = ls, le, lts, lte
      elseif es then
        s, e, text_s, text_e = es, ee, ets, ete
      else
        break
      end

      if text_s > s then
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, s - 1, { end_col = text_s - 1, conceal = '' })
      end
      if e > text_e then
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, text_e, { end_col = e, conceal = '' })
      end
      init = e + 1
    end
  end
end

return M

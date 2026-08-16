--- Locates jump targets for mep.hints' two modes, within a window's
--- visible line range. Pure buffer reads (`nvim_buf_get_lines`) plus one
--- `line('w0')`/`line('w$')` window query — no extmarks, no rendering.
local M = {}

--- The visible line range (1-indexed, inclusive) of `win` — `line('w0')`/
--- `line('w$')`, evaluated in `win`'s own context via `nvim_win_call` so
--- this is correct even when `win` isn't the current window.
function M.visible_range(win)
  local range = vim.api.nvim_win_call(win, function()
    return { vim.fn.line('w0'), vim.fn.line('w$') }
  end)
  return range[1], range[2]
end

--- Every visible word-start position in `bufnr` across `[first, last]`
--- (1-indexed, inclusive lines): the first byte column of each maximal
--- run of `%w`/`_` characters, per line. Returns a list of
--- `{ lnum, col, len }` (`col` 0-indexed byte offset), top-to-bottom,
--- left-to-right.
function M.word_starts(bufnr, first, last)
  local out = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  for i, line in ipairs(lines) do
    local lnum = first + i - 1
    local search_from = 1
    while true do
      local s, e = string.find(line, '[%w_]+', search_from)
      if not s then
        break
      end
      out[#out + 1] = { lnum = lnum, col = s - 1, len = e - s + 1 }
      search_from = e + 1
    end
  end
  return out
end

--- Every occurrence of literal single character `char` in `bufnr` across
--- `[first, last]` (1-indexed, inclusive lines), same `{lnum, col, len}`
--- shape as word_starts. A plain (non-pattern) search, so any
--- Lua-pattern-special character in `char` still matches itself
--- literally.
function M.char_matches(bufnr, first, last, char)
  local out = {}
  if not char or char == '' then
    return out
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  for i, line in ipairs(lines) do
    local lnum = first + i - 1
    local search_from = 1
    while true do
      local s = string.find(line, char, search_from, true)
      if not s then
        break
      end
      out[#out + 1] = { lnum = lnum, col = s - 1, len = #char }
      search_from = s + #char
    end
  end
  return out
end

return M

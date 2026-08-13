--- Buffer-word completion: the current buffer's own keyword-shaped
--- tokens matching the prefix — Vim's own `<C-n>`/`<C-p>` keyword
--- completion, folded into mep.completion's unified popup instead of
--- being its own separate mode. Always available (no external tool, no
--- LSP client needed) — the sensible always-on fallback source.
---
--- A **source** is a module exposing `complete(ctx, callback)`: `ctx`
--- is `{ bufnr, win, lnum, col, line, prefix, startcol }` (see
--- `mep.completion.engine`'s own header comment for exactly what each
--- field means); call `callback(items)` — synchronously or later,
--- doesn't matter which — with a list of `complete-items`-shaped
--- tables (`:help complete-items`): `{ word, abbr, kind, menu, info,
--- ... }`. This module is a good reference for the *simplest* possible
--- source (fully synchronous, no external state) — see
--- `mep.completion.sources.lsp` for an async one.
local M = {}

-- Cheap safety valve against a pathologically large buffer making every
-- keystroke scan the whole thing.
local MAX_LINES = 20000

function M.complete(ctx, callback)
  if ctx.prefix == '' or not vim.api.nvim_buf_is_valid(ctx.bufnr) then
    callback({})
    return
  end

  local line_count = math.min(vim.api.nvim_buf_line_count(ctx.bufnr), MAX_LINES)
  local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, line_count, false)
  local seen = {}
  local items = {}
  for _, line in ipairs(lines) do
    for word in line:gmatch('[%w_]+') do
      if #word > #ctx.prefix and word:sub(1, #ctx.prefix) == ctx.prefix and not seen[word] then
        seen[word] = true
        items[#items + 1] = { word = word, kind = 'Buffer', menu = '[Buffer]' }
      end
    end
  end
  callback(items)
end

return M

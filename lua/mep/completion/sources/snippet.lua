--- Snippet-trigger completion: `mep.snippet.registry`'s own per-filetype
--- triggers, folded into mep.completion's unified popup. A soft
--- dependency on `mep.snippet` (`require`d lazily inside `M.complete`,
--- `pcall`'d) — mep.completion stays fully functional without it, same
--- posture as `mep.completion.sources.lsp`'s own soft `mep.org.
--- polyglot` dependency.
---
--- Each item's body rides along as a JSON-encoded `user_data` (see
--- `mep.completion.engine.encode_snippet_user_data`) — accepting the
--- item inserts the trigger word literally (Neovim's own `complete()`
--- behavior), then `mep.completion.engine`'s own `CompleteDone` handler
--- swaps it for the real expansion via `mep.snippet.expand`.
local M = {}

function M.complete(ctx, callback)
  local ok, snippet = pcall(require, 'mep.snippet')
  if not ok then
    callback({})
    return
  end

  local engine = require('mep.completion.engine')
  local filetype = vim.bo[ctx.bufnr].filetype
  local items = {}
  for _, snip in ipairs(snippet.registry.get(filetype)) do
    if snip.trigger:sub(1, #ctx.prefix) == ctx.prefix then
      items[#items + 1] = {
        word = snip.trigger,
        abbr = snip.trigger,
        kind = 'Snippet',
        menu = '[snip]',
        info = snip.body,
        user_data = engine.encode_snippet_user_data(snip.body),
      }
    end
  end
  callback(items)
end

return M

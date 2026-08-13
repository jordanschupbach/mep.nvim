--- LSP completion: queries every client attached to the buffer that
--- supports `textDocument/completion` (however they were started — this
--- needs no direct coupling to `mep.lsp` specifically, just Neovim's own
--- client registry, which any `mep.lsp`-started client is naturally
--- part of) and converts `CompletionItem`s into mep.completion's generic
--- item shape.
---
--- **Scope note**: uses `item.insertText or item.label` as the inserted
--- text against `mep.completion.engine`'s own simple keyword-prefix
--- replacement range, not the item's own (possibly different)
--- `textEdit` range — adequate for the common case, not a full LSP
--- `textEdit` implementation. Snippet-shaped `insertText` (`$1`/`$0`
--- placeholders, when the item's `insertTextFormat` is `Snippet`) is
--- inserted as literal text, not expanded — this project has no snippet
--- engine of its own.
local M = {}

local KIND_NAMES = {
  [1] = 'Text',
  [2] = 'Method',
  [3] = 'Function',
  [4] = 'Constructor',
  [5] = 'Field',
  [6] = 'Variable',
  [7] = 'Class',
  [8] = 'Interface',
  [9] = 'Module',
  [10] = 'Property',
  [11] = 'Unit',
  [12] = 'Value',
  [13] = 'Enum',
  [14] = 'Keyword',
  [15] = 'Snippet',
  [16] = 'Color',
  [17] = 'File',
  [18] = 'Reference',
  [19] = 'Folder',
  [20] = 'EnumMember',
  [21] = 'Constant',
  [22] = 'Struct',
  [23] = 'Event',
  [24] = 'Operator',
  [25] = 'TypeParameter',
}
M.KIND_NAMES = KIND_NAMES

function M.complete(ctx, callback)
  local clients = vim.lsp.get_clients({ bufnr = ctx.bufnr, method = 'textDocument/completion' })
  if #clients == 0 then
    callback({})
    return
  end

  local remaining = #clients
  local collected = {}
  for _, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(ctx.win, client.offset_encoding)
    client:request('textDocument/completion', params, function(_, result)
      remaining = remaining - 1
      local raw = (result and (result.items or result)) or {}
      for _, item in ipairs(raw) do
        collected[#collected + 1] = {
          word = item.insertText or item.label,
          abbr = item.label,
          kind = KIND_NAMES[item.kind] or 'Text',
          menu = '[' .. client.name .. ']',
          info = item.detail or '',
        }
      end
      if remaining == 0 then
        callback(collected)
      end
    end, ctx.bufnr)
  end
end

return M

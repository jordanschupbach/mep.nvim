--- LSP document-symbol fetching for mep.symbols: pure request/flatten
--- logic, no window/buffer code — see mep.symbols.ui for rendering.
--- Queries whichever client is already attached (however it was
--- started — no direct coupling to mep.lsp specifically, same
--- "any attached client will do" stance mep.completion.sources.lsp
--- takes for completion).
local M = {}

-- The real LSP SymbolKind enum (`textDocument/documentSymbol`'s own
-- response), not mep.completion.sources.lsp's CompletionItemKind table —
-- same numeric-enum shape, different spec, easy to confuse.
M.KIND_NAMES = {
  [1] = 'File',
  [2] = 'Module',
  [3] = 'Namespace',
  [4] = 'Package',
  [5] = 'Class',
  [6] = 'Method',
  [7] = 'Property',
  [8] = 'Field',
  [9] = 'Constructor',
  [10] = 'Enum',
  [11] = 'Interface',
  [12] = 'Function',
  [13] = 'Variable',
  [14] = 'Constant',
  [15] = 'String',
  [16] = 'Number',
  [17] = 'Boolean',
  [18] = 'Array',
  [19] = 'Object',
  [20] = 'Key',
  [21] = 'Null',
  [22] = 'EnumMember',
  [23] = 'Struct',
  [24] = 'Event',
  [25] = 'Operator',
  [26] = 'TypeParameter',
}

--- Flatten a `textDocument/documentSymbol` result into document order —
--- handles both the hierarchical `DocumentSymbol[]` shape (`range`,
--- optional `children`) and the flat `SymbolInformation[]` shape
--- (`location.range`, no `children`) a server may return instead. Each
--- entry: `{ name, kind, kind_name, depth (0-based), lnum (1-based),
--- col (0-based) }` — `lnum`/`col` are the symbol's own `range.start`,
--- passed straight through as a plain Neovim cursor position rather than
--- converted from the LSP position's UTF-16 code-unit `character` to a
--- byte column (`mep.completion.sources.lsp`'s own request path leaves
--- that conversion to Neovim's built-in `vim.lsp.buf.*` handlers instead
--- of doing it by hand; this module builds its own jump target, so it's
--- a deliberate simplification here — correct for any ASCII symbol name
--- prefix, which covers the overwhelming majority of real code).
function M.flatten(raw)
  local out = {}
  local function walk(items, depth)
    for _, item in ipairs(items or {}) do
      local range = item.range or (item.location and item.location.range)
      if range then
        out[#out + 1] = {
          name = item.name,
          kind = item.kind,
          kind_name = M.KIND_NAMES[item.kind] or 'Unknown',
          depth = depth,
          lnum = range.start.line + 1,
          col = range.start.character,
        }
      end
      if item.children then
        walk(item.children, depth + 1)
      end
    end
  end
  walk(raw, 0)
  return out
end

--- Request document symbols for `bufnr` from its first attached client
--- that supports `textDocument/documentSymbol`, flattened via
--- `M.flatten`. Calls `callback(symbols, err)`: `symbols` is nil (with
--- `err` a message) when no such client is attached, or the request
--- itself errors; otherwise a (possibly empty, for a file with no
--- symbols) flat list and `err = nil`.
function M.request(bufnr, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/documentSymbol' })
  if #clients == 0 then
    callback(nil, 'no LSP client supporting documentSymbol attached to this buffer')
    return
  end
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  clients[1]:request('textDocument/documentSymbol', params, function(err, result)
    if err then
      callback(nil, err.message or tostring(err))
      return
    end
    callback(M.flatten(result), nil)
  end, bufnr)
end

return M

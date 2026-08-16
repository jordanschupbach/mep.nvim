--- Structured `textDocument/signatureHelp` fetching for mep.docs — the
--- same request `vim.lsp.buf.signature_help()` (mep.lsp's own `<C-k>`)
--- makes, but parsed here into plain `name, params` instead of shown as
--- a popup, so `mep.docs.generate` can feed real LSP-derived parameter
--- names into its docstring skeleton rather than falling back to
--- `mep.docs.parser`'s own regex guess. Same "any attached client will
--- do" stance `mep.symbols.lsp`/`mep.completion.sources.lsp` already
--- take — no coupling to mep.lsp specifically.
local M = {}

--- A signature's `parameters[i].label` is either the parameter's own
--- text directly, or a `[start, end]` UTF-16-code-unit pair into the
--- signature's own `label` string to slice out instead (the LSP spec's
--- own two allowed shapes). Byte-slicing a `[start, end]` pair as if it
--- were already a byte offset is only exactly correct for an
--- ASCII-only signature — the same simplification `mep.symbols.lsp`'s
--- own header comment documents for its jump-target columns.
local function param_label(signature, index)
  local param = signature.parameters and signature.parameters[index]
  if not param then
    return nil
  end
  if type(param.label) == 'string' then
    return param.label
  end
  if type(param.label) == 'table' then
    local s, e = param.label[1], param.label[2]
    return signature.label:sub(s + 1, e)
  end
  return nil
end

--- Parse a raw `SignatureHelp` response into `name, params` — `name` is
--- the active signature's label up to its first `(`; `params` is the
--- active signature's own parameter labels, in order. Returns `nil` for
--- a response with no signatures at all (a client that supports the
--- method but has nothing to offer at this position).
function M.parse(result)
  if not result or not result.signatures or #result.signatures == 0 then
    return nil
  end
  local index = (result.activeSignature or 0) + 1
  local signature = result.signatures[index] or result.signatures[1]
  local name = signature.label:match('^([%w_.:]+)%s*%(') or signature.label
  local params = {}
  for i = 1, #(signature.parameters or {}) do
    local label = param_label(signature, i)
    if label then
      params[#params + 1] = label
    end
  end
  return name, params
end

--- Request signature help at the cursor position in `win` (`bufnr` is
--- `win`'s buffer), from the first attached client that supports
--- `textDocument/signatureHelp`. Calls `callback(name, params)` — both
--- `nil` if no such client is attached, the request errors, or the
--- response has no signatures at all.
function M.request(bufnr, win, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/signatureHelp' })
  if #clients == 0 then
    callback(nil, nil)
    return
  end
  local client = clients[1]
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  client:request('textDocument/signatureHelp', params, function(err, result)
    if err or not result then
      callback(nil, nil)
      return
    end
    local name, parsed_params = M.parse(result)
    callback(name, parsed_params)
  end, bufnr)
end

return M

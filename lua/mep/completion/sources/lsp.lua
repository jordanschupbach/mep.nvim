--- LSP completion: queries every client attached to the buffer that
--- supports `textDocument/completion` (however they were started — this
--- needs no direct coupling to `mep.lsp` specifically, just Neovim's own
--- client registry, which any `mep.lsp`-started client is naturally
--- part of) and converts `CompletionItem`s into mep.completion's generic
--- item shape.
---
--- Inside a `#+begin_src <lang> ... #+end_src` block in an org buffer
--- with `mep.org.polyglot` active, completions instead come from *that
--- language's* own attached client: `mep.org.polyglot` keeps a hidden
--- "shadow buffer" per language in sync with the org buffer, at
--- identical line/column positions (see its own header comment), so a
--- request just needs to ask the shadow buffer's client about the real
--- cursor position — same trick `mep.org.polyglot`'s own hover/
--- definition/etc. bridge uses. This is a *soft* dependency: `require`d
--- lazily inside `M.complete`, `pcall`'d, and a no-op fallback to
--- `ctx.bufnr` if `mep.org` isn't present/loaded at all — mep.completion
--- otherwise has zero coupling to mep.org, and stays fully functional
--- without it.
---
--- **Scope note**: uses `item.insertText or item.label` as the inserted
--- text against `mep.completion.engine`'s own simple keyword-prefix
--- replacement range, not the item's own (possibly different)
--- `textEdit` range — adequate for the common case, not a full LSP
--- `textEdit` implementation. Snippet-shaped `insertText` (`$1`/`$0`
--- placeholders, when the item's `insertTextFormat` is `2`, LSP's
--- `InsertTextFormat.Snippet`) rides along as a `user_data` marker (see
--- `mep.completion.engine.encode_snippet_user_data`) and is expanded
--- through `mep.snippet` once accepted — see that module's own
--- `CompleteDone` handling.
local M = {}

local INSERT_TEXT_FORMAT_SNIPPET = 2

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

--- `ctx.bufnr` unchanged, unless `ctx` is inside a src block in an org
--- buffer `mep.org.polyglot` has a shadow buffer for — then that shadow
--- buffer's own number, so client lookup below finds *its* client
--- rather than finding none at all on the (LSP-client-less) org buffer.
local function target_bufnr(ctx)
  local ok, polyglot = pcall(require, 'mep.org.polyglot')
  if not ok then
    return ctx.bufnr
  end
  local context_ok, poly_ctx = pcall(polyglot.context_at_cursor, ctx.bufnr, ctx.lnum)
  if context_ok and poly_ctx then
    return poly_ctx.shadow_bufnr
  end
  return ctx.bufnr
end

function M.complete(ctx, callback)
  local bufnr = target_bufnr(ctx)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/completion' })
  if #clients == 0 then
    callback({})
    return
  end

  local remaining = #clients
  local collected = {}
  for _, client in ipairs(clients) do
    -- Position computed from the *real* cursor/window (so multi-byte
    -- columns on this exact line convert correctly). When redirected to a
    -- shadow buffer, the URI is repointed at `bufnr` too — safe because a
    -- src block's body line is copied into its shadow buffer completely
    -- unmodified (see mep.org.polyglot's own header comment), so the two
    -- are byte-for-byte identical at this line. Left untouched otherwise,
    -- so `make_position_params`'s own URI (and whatever shape it returns)
    -- passes through exactly as before this source knew about polyglot.
    local params = vim.lsp.util.make_position_params(ctx.win, client.offset_encoding)
    if bufnr ~= ctx.bufnr then
      params.textDocument = params.textDocument or {}
      params.textDocument.uri = vim.uri_from_bufnr(bufnr)
    end
    client:request('textDocument/completion', params, function(_, result)
      remaining = remaining - 1
      local raw = (result and (result.items or result)) or {}
      for _, item in ipairs(raw) do
        local word = item.insertText or item.label
        local user_data = ''
        if item.insertTextFormat == INSERT_TEXT_FORMAT_SNIPPET then
          user_data = require('mep.completion.engine').encode_snippet_user_data(word)
        end
        collected[#collected + 1] = {
          word = word,
          abbr = item.label,
          kind = KIND_NAMES[item.kind] or 'Text',
          menu = '[' .. client.name .. ']',
          info = item.detail or '',
          user_data = user_data,
        }
      end
      if remaining == 0 then
        callback(collected)
      end
    end, bufnr)
  end
end

return M

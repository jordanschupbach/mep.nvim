--- Buffer-local wiring for an attached LSP client (`LspAttach`) — mep.lsp's
--- own version of what mep.org.org/mep.filetree/mep.sidebar each already
--- do for their own domain: turn config into real keymaps.
local M = {}

--- Bind `keymaps` (`mep.lsp.config.defaults.keymaps`' own shape) as
--- buffer-local mappings in `bufnr`, and turn on native LSP completion
--- for it (`vim.lsp.completion.enable` — Neovim's own built-in
--- completion menu, no separate completion-engine plugin needed) if
--- `completion_enabled` and `client` actually supports
--- `textDocument/completion`.
---
--- The keymaps themselves are bound unconditionally, deliberately not
--- capability-gated per client (unlike completion) — a narrower client
--- just answers "method not supported" harmlessly for whichever of
--- these it doesn't implement, the same tradeoff nvim-lspconfig's own
--- long-standing example config made rather than checking `client:
--- supports_method(...)` for every single mapping.
function M.bind(bufnr, client, keymaps, completion_enabled)
  local map_opts = { buffer = bufnr, silent = true, nowait = true }
  local function map_all(mode, lhs_list, fn, desc)
    local opts = vim.tbl_extend('force', map_opts, { desc = desc })
    for _, lhs in ipairs(lhs_list or {}) do
      vim.keymap.set(mode, lhs, fn, opts)
    end
  end

  map_all('n', keymaps.goto_definition, vim.lsp.buf.definition, 'lsp: goto definition')
  map_all('n', keymaps.goto_declaration, vim.lsp.buf.declaration, 'lsp: goto declaration')
  map_all('n', keymaps.references, vim.lsp.buf.references, 'lsp: references')
  map_all('n', keymaps.implementation, vim.lsp.buf.implementation, 'lsp: goto implementation')
  map_all('n', keymaps.type_definition, vim.lsp.buf.type_definition, 'lsp: goto type definition')
  map_all('n', keymaps.hover, vim.lsp.buf.hover, 'lsp: hover')
  map_all({ 'n', 'i' }, keymaps.signature_help, vim.lsp.buf.signature_help, 'lsp: signature help')
  map_all('n', keymaps.rename, vim.lsp.buf.rename, 'lsp: rename')
  map_all({ 'n', 'v' }, keymaps.code_action, vim.lsp.buf.code_action, 'lsp: code action')
  map_all('n', keymaps.format, function()
    vim.lsp.buf.format({ async = true, bufnr = bufnr })
  end, 'lsp: format')
  map_all('n', keymaps.diagnostic_prev, vim.diagnostic.goto_prev, 'lsp: previous diagnostic')
  map_all('n', keymaps.diagnostic_next, vim.diagnostic.goto_next, 'lsp: next diagnostic')
  map_all('n', keymaps.diagnostic_float, vim.diagnostic.open_float, 'lsp: show diagnostic')

  if completion_enabled and client.supports_method and client:supports_method('textDocument/completion') then
    vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
  end
end

return M

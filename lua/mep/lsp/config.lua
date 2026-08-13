local M = {}

M.defaults = {
  -- Which curated (`mep.lsp.servers.registry`) + `servers` (below)
  -- configs to actually activate: `true` (default) means every one
  -- whose `cmd[1]` is found on `PATH` (`vim.fn.executable`); a list of
  -- names activates just those (still gated on being found on `PATH` —
  -- this never tries to start something that isn't actually installed);
  -- `false`/`nil` registers configs (so `vim.lsp.enable(name)` still
  -- works if you call it yourself) without auto-activating any of them
  -- — `mep.treesitter.config.defaults.ensure_installed`'s own
  -- true/list/false shape, applied here.
  enable = true,
  -- Extra server configs (or overrides of a curated one — merged via
  -- `vim.lsp.config(name, cfg)`, not replaced), same `vim.lsp.Config`
  -- shape as `mep.lsp.servers.registry`'s own entries: `{ cmd = {...},
  -- filetypes = {...}, root_markers = {...} }`.
  servers = {},
  -- Forwarded to `vim.diagnostic.config()`.
  diagnostics = {
    virtual_text = true,
    signs = true,
    underline = true,
    severity_sort = true,
    float = { border = 'rounded' },
  },
  -- Native LSP-driven completion (`vim.lsp.completion.enable`, Neovim's
  -- own built-in completion menu — no separate completion-engine plugin
  -- needed), turned on per-buffer on `LspAttach` for any client that
  -- supports it.
  completion = true,
  keymaps = {
    -- The classic gd/gD/gr/gi vocabulary (nvim-lspconfig's own
    -- long-standing example config popularized these) rather than
    -- Neovim >= 0.11's own built-in `gr`-prefixed defaults
    -- (`grn`/`gra`/`grr`/`gri`/...) — both can coexist; this is an
    -- additional, more traditional set, not a replacement.
    goto_definition = { 'gd' },
    goto_declaration = { 'gD' },
    references = { 'gr' },
    implementation = { 'gi' },
    type_definition = { '<leader>lt' },
    hover = { 'K' },
    signature_help = { '<C-k>' },
    rename = { '<leader>rn' },
    code_action = { '<leader>ca' },
    format = { '<leader>lf' },
    diagnostic_prev = { '[d' },
    diagnostic_next = { ']d' },
    diagnostic_float = { '<leader>le' },
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied keymaps alike) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

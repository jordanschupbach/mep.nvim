--- Annotates the end of each `#+end_src` line with its language's LSP
--- status (is any currently-attached client for that language's own
--- filetype running anywhere in this Neovim session — see `mep.org.
--- babel`'s own header comment on why a real LSP server has to exist
--- for a language to be curated into `M.languages` at all) and whether
--- its last run was served from `mep.org.babel`'s `:cache yes` cache.
--- Pure-Lua extmark bookkeeping, same pattern as `mep.org.blockhl`/
--- `.resultshl`, recomputed on buffer change via `mep.org.babel.
--- find_blocks` — except an end-of-line `virt_text` annotation (`mep.
--- diagnostics`'s own idiom) rather than a background/foreground span,
--- since this is a per-line label, not a highlighted region.
local babel = require('mep.org.babel')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_babel_status')

M.hl_group = 'MepOrgBabelStatus'

--- Give MepOrgBabelStatus a color if nothing else already has —
--- `default = true` means a user's own `:highlight MepOrgBabelStatus
--- ...` (or a colorscheme that defines it) wins over this. Linked to
--- `Comment`, matching how an unobtrusive inline annotation typically
--- reads (dimmer than the src block's own body text).
function M.define_default_hl()
  vim.api.nvim_set_hl(0, M.hl_group, { link = 'Comment', default = true })
end

-- babel language key -> Neovim filetype, for the handful where they
-- differ. Every other language key in `mep.org.babel.M.languages`
-- already matches its own filetype name (`'python'`, `'lua'`, `'go'`,
-- `'rust'`, ...), so this only needs the exceptions.
local FILETYPE_OVERRIDES = {
  csharp = 'cs',
}

local function language_filetype(lang_key)
  return FILETYPE_OVERRIDES[lang_key] or lang_key
end

--- Whether any currently-attached LSP client, anywhere in this Neovim
--- session (not scoped to `bufnr` — the org buffer itself is never
--- attached to e.g. a Python server, so this answers "is there LSP
--- support for this language active right now", not "is a client
--- attached to this specific buffer"), serves the language `block`'s
--- own filetype.
local function lsp_active_for(lang_key)
  local filetype = language_filetype(lang_key:lower())
  for _, client in ipairs(vim.lsp.get_clients({})) do
    if vim.tbl_contains(client.config.filetypes or {}, filetype) then
      return true
    end
  end
  return false
end

--- Clear every annotation extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute end-of-block annotations for every src block in `bufnr`,
--- replacing whatever was there before.
function M.apply(bufnr)
  M.clear(bufnr)
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    local args = babel.parse_header_args(block.args)
    local lsp_text = lsp_active_for(block.lang) and 'LSP ok' or 'no LSP'

    local cache_text
    if args.cache == 'yes' then
      cache_text = babel.results_cache[babel.cache_key(bufnr, block)] and 'cached' or 'not cached'
    else
      cache_text = 'live'
    end

    local text = string.format(' [%s: %s, %s]', block.lang, lsp_text, cache_text)
    vim.api.nvim_buf_set_extmark(bufnr, ns, block.end_lnum - 1, 0, {
      virt_text = { { text, M.hl_group } },
      virt_text_pos = 'eol',
    })
  end
end

return M

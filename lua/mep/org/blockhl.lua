--- Gives every `#+begin_src ... #+end_src` block a distinct background so
--- it stands out from surrounding prose. Pure-Lua extmark bookkeeping,
--- same pattern as mep.org.linkconceal: recomputed on buffer change
--- rather than baked into `queries/org/highlights.scm` — the tree-sitter
--- grammar has no node distinguishing a src block from any other
--- `#+begin_*` block (that query already treats every such block as one
--- opaque `@markup.raw.block` span), so this manages its own extmarks
--- directly, using mep.org.babel.find_blocks to locate spans.
local babel = require('mep.org.babel')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_src_block_bg')

M.hl_group = 'MepOrgSrcBlock'

--- Give MepOrgSrcBlock a background if nothing else already has —
--- `default = true` means a user's own `:highlight MepOrgSrcBlock ...`
--- (or a colorscheme that defines it) wins over this. Linked to
--- `CursorLine` rather than a hard-coded color: every colorscheme
--- defines it with a background distinct from `Normal`, so the block
--- background adapts automatically to light/dark themes instead of
--- clashing with one of them.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, M.hl_group, { link = 'CursorLine', default = true })
end

--- Clear every background extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute background extmarks for every src block in `bufnr`,
--- replacing whatever was there before. Covers the `#+begin_src`/
--- `#+end_src` delimiter lines too, matching real org-mode's src-block
--- face spanning the whole block.
function M.apply(bufnr)
  M.clear(bufnr)
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    for lnum = block.start_lnum, block.end_lnum do
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
        end_row = lnum,
        hl_group = M.hl_group,
        hl_eol = true,
        -- `vim.highlight.priorities.treesitter` (100, confirmed via
        -- `vim.inspect(vim.highlight.priorities)`) is the priority
        -- `vim.treesitter.highlighter` itself uses for every capture —
        -- `queries/org/highlights.scm`'s own `@markup.raw.block` capture
        -- on this same span included. A plain `priority = 100` here
        -- would only be an exact *tie* with that, not a guaranteed win
        -- (confirmed empirically to lose against it for at least some
        -- capture/theme combinations); `vim.highlight.priorities.user`
        -- (200) is Neovim's own documented tier for exactly this "a
        -- plugin wants to override syntax/treesitter highlighting for a
        -- specific span" case.
        priority = 200,
      })
    end
  end
end

return M

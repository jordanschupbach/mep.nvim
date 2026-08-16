--- Gives every `#+RESULTS:` block a distinct *color*, so a src block's
--- computed output reads as a literal value rather than plain prose —
--- pure-Lua extmark bookkeeping, recomputed on buffer change rather than
--- baked into `queries/org/highlights.scm`: the grammar has no node for
--- the one-line `: value` results form at all, and its generic `(block)
--- @markup.raw.block` capture already covers a multi-line `#+begin_example`
--- body (in whatever plain color that renders, no different from any
--- other prose block) but not the `#+RESULTS:` line introducing it, so
--- this manages its own extmarks directly, using mep.org.babel.find_results
--- to locate spans. Same overall shape as mep.org.blockhl's own
--- `#+begin_src` handling, but a foreground color rather than a
--- background band — a background alone left the actual result *text*
--- unchanged (confirmed insufficiently distinct in practice).
local babel = require('mep.org.babel')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_results_block')

M.hl_group = 'MepOrgResultsBlock'

--- Give MepOrgResultsBlock a color if nothing else already has —
--- `default = true` means a user's own `:highlight MepOrgResultsBlock
--- ...` (or a colorscheme that defines it) wins over this. Linked to
--- `Constant` rather than a hard-coded color: virtually every
--- colorscheme (including every mep.theme palette, via `mep.theme.
--- engine`'s own `Constant = { fg = 'orange' }`) gives it a warm,
--- orange-toned color, and semantically a results block *is* one
--- literal, unchanging value — the same "not a hardcoded hex" reasoning
--- `MepOrgSrcBlock`'s own `CursorLine` link uses, just picking the
--- standard group whose color this feature actually wants.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, M.hl_group, { link = 'Constant', default = true })
end

--- Clear every extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute color extmarks for every `#+RESULTS:` block in `bufnr`,
--- replacing whatever was there before. Covers the `#+RESULTS:` line
--- itself (and, for the multi-line form, the `#+begin_example`/
--- `#+end_example` delimiters too), matching mep.org.blockhl's own
--- "whole span, delimiters included" treatment of src blocks.
function M.apply(bufnr)
  M.clear(bufnr)
  for _, result in ipairs(babel.find_results(bufnr)) do
    for lnum = result.start_lnum, result.end_lnum do
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
        end_row = lnum,
        hl_group = M.hl_group,
        hl_eol = true,
        -- 200 (`vim.highlight.priorities.user`), not the treesitter
        -- highlighter's own 100 — see mep.org.blockhl's own `M.apply`
        -- for why an exact tie there isn't a reliable win.
        priority = 200,
      })
    end
  end
end

return M

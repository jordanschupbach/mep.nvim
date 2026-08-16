--- Gives each org headline level its own distinct color (level 1 blue,
--- cycling through a fixed rotation after that) — the same "make a
--- specific construct visually distinct" goal as mep.org.blockhl/
--- mep.org.resultshl, but for a construct `queries/org/highlights.scm`'s
--- own header comment explains it deliberately *can't* distinguish by
--- itself: the org grammar's `headline` node has no `level` field, only
--- its literal `(stars)` text (`*`, `**`, ...), and counting those via a
--- custom Lua predicate is exactly what that query avoids depending on
--- (see its own header comment on why) — so every level currently
--- renders as the same `@markup.heading.1` capture, one flat color. Same
--- as the other two mep.org.*hl modules, this manages its own extmarks
--- directly, counting stars the same way mep.org.headline/mep.org.fold
--- already do (`#(line:match('^(%*+)'))`).
local headline = require('mep.org.headline')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_headline')

--- One color per headline level, cycling every 6 entries — matching how
--- many genuinely distinct named colors a mep.theme palette guarantees
--- (`blue/purple/green/cyan/red/yellow`; real org-mode's own 8-level
--- cycle reuses colors past its last configured level the same way).
M.hl_groups = {
  'MepOrgHeadline1',
  'MepOrgHeadline2',
  'MepOrgHeadline3',
  'MepOrgHeadline4',
  'MepOrgHeadline5',
  'MepOrgHeadline6',
}

--- `M.hl_groups[i]`'s default link target — a standard, single-color
--- group per level rather than a hardcoded hex, same "adapts to any
--- colorscheme" reasoning mep.org.blockhl/mep.org.resultshl already use.
--- Deliberately excludes `Constant` (orange) — mep.org.resultshl's own
--- color — so a `#+RESULTS:` block stays visually distinct from the
--- headline of the src block that produced it, the whole point of this
--- module existing. `plugin/mep.lua`'s own `set_highlights()` repeats
--- this same mapping (see its own comment on why: a `:colorscheme`/
--- `mep.theme.apply()` switch doesn't re-trigger `M.define_default_hl`
--- below on its own).
M.LINKS = {
  'Function', -- blue, bold
  'Define', -- purple
  'String', -- green
  'DiagnosticHint', -- cyan
  'Keyword', -- red
  'Type', -- yellow
}

--- Give each MepOrgHeadlineN a color if nothing else already has —
--- `default = true` means a user's own `:highlight MepOrgHeadlineN ...`
--- (or a colorscheme that defines it) wins over this, same as every
--- other mep.org.*hl module.
function M.define_default_hl()
  for i, group in ipairs(M.hl_groups) do
    vim.api.nvim_set_hl(0, group, { link = M.LINKS[i], default = true })
  end
end

--- The highlight group for `level` (1-indexed), cycling through
--- `M.hl_groups` past its end — matching real org-mode's own headline
--- face cycling past its last configured level.
local function group_for(level)
  return M.hl_groups[(level - 1) % #M.hl_groups + 1]
end

--- Clear every extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute color extmarks for every headline in `bufnr`, replacing
--- whatever was there before. Colors the whole line (stars through
--- title/tags), matching real org-mode's own headline face.
function M.apply(bufnr)
  M.clear(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    if headline.is_headline(line) then
      local level = #(line:match('^(%*+)'))
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
        end_row = lnum,
        hl_group = group_for(level),
        hl_eol = true,
        -- 200 (`vim.highlight.priorities.user`), not the treesitter
        -- highlighter's own 100 — a tie there is confirmed (the reason
        -- this got bumped in the first place) to lose against
        -- `queries/org/highlights.scm`'s own `@markup.heading` capture
        -- for at least some theme/capture combinations, which is
        -- exactly the "still orange" symptom this fixes: every level
        -- rendering as `Title`'s own color regardless of this module
        -- being active at all. See mep.org.blockhl's own `M.apply` for
        -- the fuller explanation.
        priority = 200,
      })
    end
  end
end

return M

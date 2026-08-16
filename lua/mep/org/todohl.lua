--- Gives each TODO-state keyword (`config.todo_keywords`) its own color —
--- real org-mode's own look (TODO red, DONE green) generalized to any
--- configured set of keywords, via `config.todo_keyword_colors`. Same
--- "manage our own extmarks, don't rely on `queries/org/highlights.scm`"
--- reasoning as mep.org.headlinehl: that query's TODO/DONE captures are
--- hardcoded literal-text matches (its own header comment explains why —
--- no custom Lua predicates, so nothing there can consult a user's
--- `todo_keywords` list), so it can't grow beyond the two default
--- keywords or take per-keyword colors from config on its own.
local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_todo')

--- Fallback palette a keyword cycles through, positional within
--- `todo_keywords`, when `config.todo_keyword_colors` has no entry for
--- it (e.g. a custom state added to `todo_keywords` without also being
--- assigned a color) — same rotation-past-a-fixed-set fallback
--- mep.org.headlinehl uses for headline levels.
M.hl_groups = {
  'MepOrgTodoKeyword1',
  'MepOrgTodoKeyword2',
  'MepOrgTodoKeyword3',
  'MepOrgTodoKeyword4',
  'MepOrgTodoKeyword5',
  'MepOrgTodoKeyword6',
}

--- `M.hl_groups[i]`'s default link target. `plugin/mep.lua`'s own
--- `set_highlights()` repeats this same mapping (see its own comment on
--- why: a `:colorscheme`/`mep.theme.apply()` switch doesn't re-trigger
--- `M.define_default_hl` below on its own).
M.LINKS = {
  'DiagnosticError', -- red
  'DiagnosticOk', -- green
  'DiagnosticWarn', -- yellow/orange
  'DiagnosticInfo', -- blue
  'DiagnosticHint', -- cyan
  'Type', -- another distinct color for anything past the above
}

--- Give each MepOrgTodoKeywordN a color if nothing else already has —
--- `default = true` means a user's own `:highlight MepOrgTodoKeywordN
--- ...` (or a colorscheme that defines it) wins over this, same as every
--- other mep.org.*hl module.
function M.define_default_hl()
  for i, group in ipairs(M.hl_groups) do
    vim.api.nvim_set_hl(0, group, { link = M.LINKS[i], default = true })
  end
end

--- Clear every extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Find `line`'s TODO keyword (the first word of `todo_keywords` it
--- starts with, right after the stars — same rule mep.org.headline.parse
--- uses), if any. Returns the keyword, its 1-based index within
--- `todo_keywords` (for `M.hl_groups` cycling), and its 0-based
--- start/end byte columns (for `nvim_buf_set_extmark`) — computed
--- directly against `line`'s own text rather than reusing
--- `headline.parse`'s return value, which doesn't carry column
--- positions.
local function match_keyword(line, todo_keywords)
  local prefix, rest = line:match('^(%*+%s+)(.*)$')
  if not prefix then
    return nil
  end
  for i, kw in ipairs(todo_keywords) do
    if rest == kw or rest:sub(1, #kw + 1) == kw .. ' ' then
      return kw, i, #prefix, #prefix + #kw
    end
  end
  return nil
end

--- The highlight group for `keyword` at `index` within `todo_keywords`:
--- `colors[keyword]` if configured (any real highlight group — built-in,
--- a colorscheme's own, or one of your own — not just one of
--- `M.hl_groups`), else `M.hl_groups` cycling by `index`.
local function group_for(keyword, index, colors)
  return (colors and colors[keyword]) or M.hl_groups[(index - 1) % #M.hl_groups + 1]
end

--- Recompute color extmarks for every headline's TODO keyword in
--- `bufnr`, replacing whatever was there before. Colors just the keyword
--- itself (not the whole line — that's mep.org.headlinehl's job), at a
--- higher priority (210) than headlinehl's own whole-line color (200) so
--- the keyword's color always wins over the headline's, same as real
--- org-mode's TODO/DONE faces overriding its headline face.
function M.apply(bufnr, todo_keywords, todo_keyword_colors)
  M.clear(bufnr)
  if not todo_keywords or #todo_keywords == 0 then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    local keyword, index, start_col, end_col = match_keyword(line, todo_keywords)
    if keyword then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, start_col, {
        end_col = end_col,
        hl_group = group_for(keyword, index, todo_keyword_colors),
        priority = 210,
      })
    end
  end
end

return M

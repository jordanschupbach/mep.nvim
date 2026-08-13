--- Sparse tree: given a predicate over headlines, fold away everything
--- except matching headlines (with their own immediate body text) and
--- their ancestor headlines (the "path" down to each match) — real
--- org-mode's `C-c /`. Uses manual folds, the same technique
--- mep.org.narrow and mep.org.visibility already use for their own
--- fold-based views; `clear` is meant to be tried alongside
--- `mep.org.narrow.widen` by the `widen` keymap (both are safe no-ops
--- when their own state isn't present for a given window), so one key
--- reverts whichever fold-restricting feature was last used.
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')

local M = {}

-- winid -> { foldmethod, foldenable } saved before show_matching first
-- touched that window, so clear() can restore it.
local saved = {}

--- Fold `bufnr` (shown in `win`) so only headlines satisfying
--- `predicate(bufnr, lnum)` — plus their own immediate body text (up to
--- the next headline) and every ancestor headline above them — stay
--- visible. Returns the number of matching headlines.
function M.show_matching(bufnr, win, predicate)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local matched = {}
  local match_count = 0
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) and predicate(bufnr, i) then
      matched[i] = true
      match_count = match_count + 1
    end
  end

  local visible = {}
  for lnum in pairs(matched) do
    local stop = outline.next_headline(bufnr, lnum)
    for l = lnum, (stop and stop - 1 or #lines) do
      visible[l] = true
    end
    local anc = outline.parent_headline(bufnr, lnum)
    while anc do
      visible[anc] = true
      anc = outline.parent_headline(bufnr, anc)
    end
  end

  if not saved[win] then
    saved[win] = { foldmethod = vim.wo[win].foldmethod, foldenable = vim.wo[win].foldenable }
  end

  vim.api.nvim_win_call(win, function()
    vim.wo[win].foldmethod = 'manual'
    vim.cmd('normal! zE')
    local i = 1
    while i <= #lines do
      if not visible[i] then
        local j = i
        while j <= #lines and not visible[j] do
          j = j + 1
        end
        vim.cmd(string.format('%d,%dfold', i, j - 1))
        i = j
      else
        i = i + 1
      end
    end
  end)

  return match_count
end

--- Undo `show_matching`, restoring `win`'s previous fold configuration.
--- Returns true, or nil if `win` was never touched by `show_matching`.
function M.clear(win)
  local s = saved[win]
  if not s then
    return nil
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zE')
    vim.wo[win].foldmethod = s.foldmethod
    vim.wo[win].foldenable = s.foldenable
  end)
  saved[win] = nil
  return true
end

--- Interactively sparse-tree-search by tag match expression (see
--- mep.org.tagmatch), evaluated against each headline's
--- mep.org.tags.effective_tags (inheritance-aware).
function M.tag_search_interactive(bufnr, win, todo_keywords)
  local tagmatch = require('mep.org.tagmatch')
  local tags_mod = require('mep.org.tags')
  vim.ui.input({ prompt = 'Sparse tree tag match (e.g. +work-urgent): ' }, function(expr)
    if not expr or expr == '' then
      return
    end
    local groups = tagmatch.parse(expr)
    if not groups then
      vim.notify('mep.org: invalid tag match expression', vim.log.levels.WARN)
      return
    end
    local n = M.show_matching(bufnr, win, function(b, lnum)
      return tagmatch.matches(groups, tags_mod.effective_tags(b, lnum, todo_keywords))
    end)
    vim.notify(string.format('mep.org: sparse tree — %d match(es)', n), vim.log.levels.INFO)
  end)
end

--- Interactively sparse-tree-search by TODO state, picking the keyword
--- from `todo_keywords` via `mep.picker`.
function M.todo_search_interactive(bufnr, win, todo_keywords)
  if not todo_keywords or #todo_keywords == 0 then
    vim.notify('mep.org: no todo_keywords configured', vim.log.levels.WARN)
    return
  end
  require('mep.picker').start({
    prompt_title = 'Sparse tree by TODO state',
    items = todo_keywords,
    entry_to_string = function(kw)
      return kw
    end,
    on_select = function(kw)
      local n = M.show_matching(bufnr, win, function(b, lnum)
        local line = vim.api.nvim_buf_get_lines(b, lnum - 1, lnum, false)[1]
        local parsed = headline_mod.parse(line, todo_keywords)
        return parsed.todo == kw
      end)
      vim.notify(string.format('mep.org: sparse tree — %d match(es)', n), vim.log.levels.INFO)
    end,
  })
end

--- Prompt for a sparse-tree search kind (tag or TODO state) via
--- `vim.ui.select`, then delegate to the matching `*_interactive`
--- function above — real org-mode's `C-c /` similarly asks for a search
--- type before its own query prompt.
function M.search_interactive(bufnr, win, todo_keywords)
  vim.ui.select({ 'tag', 'todo' }, { prompt = 'Sparse tree by:' }, function(choice)
    if choice == 'tag' then
      M.tag_search_interactive(bufnr, win, todo_keywords)
    elseif choice == 'todo' then
      M.todo_search_interactive(bufnr, win, todo_keywords)
    end
  end)
end

return M

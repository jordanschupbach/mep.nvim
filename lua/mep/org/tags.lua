--- Tags beyond Phase 0's basic `:tag1:tag2:` parsing (mep.org.headline):
--- inheritance, setting/toggling a headline's own tags, column
--- alignment, and a fast single-key tag-selection popup. See
--- mep.org.tagmatch for the `+tag-tag` filter-expression side of tags
--- (a separate module since it doesn't touch buffers at all).
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')

local M = {}

--- The headline at `lnum`'s own (non-inherited) tags, or {} if `lnum`
--- isn't inside a headline / it has none.
function M.own_tags(bufnr, lnum, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return {}
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})
  return parsed.tags or {}
end

--- Every tag that applies to the headline at `lnum` for search/matching
--- purposes: its own tags plus every ancestor's tags (real org-mode tag
--- inheritance), deduped — own tags first in their original order, then
--- each ancestor's (nearest first) not already present. {} if `lnum`
--- isn't inside a headline.
function M.effective_tags(bufnr, lnum, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return {}
  end
  local seen = {}
  local result = {}
  local cur = at
  while cur do
    for _, tag in ipairs(M.own_tags(bufnr, cur, todo_keywords)) do
      if not seen[tag] then
        seen[tag] = true
        result[#result + 1] = tag
      end
    end
    cur = outline.parent_headline(bufnr, cur)
  end
  return result
end

--- Set the headline at `lnum`'s own tags to exactly `tags` (replacing
--- whatever was there). Returns true, or nil if `lnum` isn't inside a
--- headline.
function M.set_tags(bufnr, lnum, tags, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})
  parsed.tags = tags
  vim.api.nvim_buf_set_lines(bufnr, at - 1, at, false, { headline_mod.render(parsed) })
  return true
end

--- Toggle `tag` on the headline at `lnum`'s own tags. Returns true if
--- the tag ended up present, false if it was removed, or nil if `lnum`
--- isn't inside a headline.
function M.toggle_tag(bufnr, lnum, tag, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local tags = M.own_tags(bufnr, at, todo_keywords)
  local new_tags = {}
  local present = true
  local found = false
  for _, t in ipairs(tags) do
    if t == tag then
      found = true
    else
      new_tags[#new_tags + 1] = t
    end
  end
  if not found then
    new_tags[#new_tags + 1] = tag
  else
    present = false
  end
  M.set_tags(bufnr, at, new_tags, todo_keywords)
  return present
end

--- Reformat a headline `line` so its trailing `:tag:` block starts at
--- 1-based `column`, padding with spaces. If the headline's own content
--- already reaches or passes that column, a single space is used
--- instead — real org-mode never truncates a headline or pushes tags
--- onto their own line to make room. A no-op (returns `line` unchanged)
--- if it has no tags.
function M.align_line(line, column, todo_keywords)
  local parsed = headline_mod.parse(line, todo_keywords or {})
  if not parsed or not parsed.tags or #parsed.tags == 0 then
    return line
  end
  local head = headline_mod.render({ level = parsed.level, todo = parsed.todo, priority = parsed.priority, title = parsed.title })
  local tags_text = ':' .. table.concat(parsed.tags, ':') .. ':'
  -- pad so the tags block's first character lands at 1-based `column`
  local pad = math.max(1, column - 1 - #head)
  return head .. string.rep(' ', pad) .. tags_text
end

--- Align every tagged headline in `bufnr` to `column` (see `align_line`).
--- Returns true if anything changed.
function M.align_buffer(bufnr, column, todo_keywords)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changed = false
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      local aligned = M.align_line(line, column, todo_keywords)
      if aligned ~= line then
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { aligned })
        changed = true
      end
    end
  end
  return changed
end

--- Assign a single-letter shortcut to each tag in `tags` (first not-yet-
--- used letter in the tag name, falling back to a digit if every letter
--- in it collides) — real org-mode's fast-tag-selection does the same
--- when `org-tag-alist` doesn't pin explicit letters. Returns a list of
--- `{ tag, key }` in the same order as `tags`; `key` is nil if no letter
--- or digit was available (26 letters + 10 digits exhausted).
function M.assign_shortcuts(tags)
  local used = {}
  local shortcuts = {}
  for _, tag in ipairs(tags) do
    local key = nil
    for i = 1, #tag do
      local c = tag:sub(i, i):lower()
      if c:match('%a') and not used[c] then
        key = c
        break
      end
    end
    if not key then
      for _, c in ipairs({ '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' }) do
        if not used[c] then
          key = c
          break
        end
      end
    end
    if key then
      used[key] = true
    end
    shortcuts[#shortcuts + 1] = { tag = tag, key = key }
  end
  return shortcuts
end

local function render_popup_lines(shortcuts, selected)
  local lines = {}
  for _, s in ipairs(shortcuts) do
    lines[#lines + 1] = string.format('[%s] %s  %s', selected[s.tag] and 'x' or ' ', s.key or '?', s.tag)
  end
  return lines
end

--- Open a small floating popup listing `configured_tags`, each with an
--- auto-assigned single-letter shortcut (see `assign_shortcuts`) and a
--- checkbox reflecting whether it's currently on the headline at `lnum`.
--- Pressing a shortcut letter toggles that tag; `<CR>` applies the
--- toggled set (via `set_tags`, then `align_line` if `align_column` is
--- given) and closes; `<Esc>`/`q` closes without applying anything —
--- real org-mode's fast-tag-selection (`C-c C-c` on a headline in real
--- org; kept separate from this project's own `<C-c><C-c>`, which is
--- already dedicated to checkbox toggling). No-op if `lnum` isn't inside
--- a headline or `configured_tags` is empty.
function M.select_interactive(bufnr, lnum, configured_tags, todo_keywords, align_column)
  local at = outline.current_headline(bufnr, lnum)
  if not at or not configured_tags or #configured_tags == 0 then
    return
  end

  local shortcuts = M.assign_shortcuts(configured_tags)
  local selected = {}
  for _, tag in ipairs(M.own_tags(bufnr, at, todo_keywords)) do
    selected[tag] = true
  end

  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[popup_buf].bufhidden = 'wipe'
  local lines = render_popup_lines(shortcuts, selected)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.bo[popup_buf].modifiable = false

  local width = 8
  for _, l in ipairs(lines) do
    width = math.max(width, #l + 2)
  end

  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = #shortcuts,
    style = 'minimal',
    border = 'rounded',
  })

  local function redraw()
    vim.bo[popup_buf].modifiable = true
    vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, render_popup_lines(shortcuts, selected))
    vim.bo[popup_buf].modifiable = false
  end

  local function close()
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
  end

  local map_opts = { buffer = popup_buf, nowait = true, silent = true }
  for _, s in ipairs(shortcuts) do
    if s.key then
      vim.keymap.set('n', s.key, function()
        selected[s.tag] = not selected[s.tag]
        redraw()
      end, map_opts)
    end
  end

  vim.keymap.set('n', '<CR>', function()
    local new_tags = {}
    for _, s in ipairs(shortcuts) do
      if selected[s.tag] then
        new_tags[#new_tags + 1] = s.tag
      end
    end
    close()
    M.set_tags(bufnr, at, new_tags, todo_keywords)
    if align_column then
      local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
      vim.api.nvim_buf_set_lines(bufnr, at - 1, at, false, { M.align_line(line, align_column, todo_keywords) })
    end
  end, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)
  vim.keymap.set('n', 'q', close, map_opts)
end

return M

--- Org links: `[[target]]` and `[[target][description]]`. Pure
--- line-pattern parsing (no tree-sitter needed — the real grammar has no
--- dedicated link/link_desc node at all, confirmed against
--- node-types.json while building Phase 0's highlight query), plus
--- interactive follow/insert/store commands. Concealment of the raw
--- `[[...]]` syntax lives in mep.org.linkconceal, a separate module
--- since it's pure extmark bookkeeping with no link-semantics of its
--- own.
---
--- `id:`/`#custom-id` targets need a headline's own `:ID:`/`:CUSTOM_ID:`
--- property, read via mep.org.property (Phase 7's real property-drawer
--- parsing — this module used to carry its own narrow ad-hoc scanner for
--- just those two keys, since property.lua didn't exist yet).
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')
local property = require('mep.org.property')

local M = {}

M.stored = nil

local WITH_DESC = '%[%[([^%[%]]+)%]%[([^%[%]]+)%]%]'
local BARE = '%[%[([^%[%]]+)%]%]'

--- Find the first link in `line` at or after byte index `init` (default
--- 1). Returns `start_col, end_col` (1-based, inclusive), `target`, and
--- `description` (nil if the link has none), or nil if there isn't one.
function M.find(line, init)
  init = init or 1
  local s1, e1, t1, d1 = line:find(WITH_DESC, init)
  local s2, e2, t2 = line:find(BARE, init)
  if s1 and (not s2 or s1 <= s2) then
    return s1, e1, t1, d1
  elseif s2 then
    return s2, e2, t2, nil
  end
  return nil
end

--- Find the link in `line` that contains 0-based column `col` (Neovim
--- cursor convention), or nil.
function M.find_at_col(line, col)
  local init = 1
  while true do
    local s, e, target, description = M.find(line, init)
    if not s then
      return nil
    end
    if col >= s - 1 and col < e then
      return s, e, target, description
    end
    if s - 1 > col then
      return nil
    end
    init = e + 1
  end
end

--- Parse a single standalone link string in full, or nil if `text`
--- isn't exactly one link.
function M.parse(text)
  local s, e, target, description = M.find(text, 1)
  if s == 1 and e == #text then
    return { target = target, description = description }
  end
  return nil
end

--- Rebuild a link string from `{ target, description }` (`description`
--- may be nil/empty for a bare `[[target]]`).
function M.render(link)
  if link.description and link.description ~= '' then
    return '[[' .. link.target .. '][' .. link.description .. ']]'
  end
  return '[[' .. link.target .. ']]'
end

--- The line number of the first headline in `bufnr` whose title is
--- exactly `title`, or nil. Deliberately simpler than real org-mode's
--- fuzzy/regex text search for a bare link target.
function M.find_by_title(bufnr, title, todo_keywords)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      local parsed = headline_mod.parse(line, todo_keywords or {})
      if parsed.title == title then
        return i
      end
    end
  end
  return nil
end

--- Open `url` with the system opener (`vim.ui.open`, Neovim 0.10+).
--- Returns true on success, false (with a notification) if `vim.ui.open`
--- isn't available.
function M.open_url(url)
  if vim.ui.open then
    vim.ui.open(url)
    return true
  end
  vim.notify('mep.org: vim.ui.open unavailable (needs Neovim 0.10+); cannot open ' .. url, vim.log.levels.WARN)
  return false
end

--- Open a `file:`-style target: `path` or `path::N` (jump to line N) or
--- `path::*Heading` (jump to a headline titled `Heading` in the opened
--- file). Returns true on success.
function M.open_file(path, todo_keywords)
  local file_part, locator = path:match('^([^:]*)::(.*)$')
  file_part = file_part ~= '' and file_part or path
  if file_part == '' then
    vim.notify('mep.org: empty file link target', vim.log.levels.WARN)
    return false
  end
  local ok = pcall(vim.cmd.edit, vim.fn.fnameescape(file_part))
  if not ok then
    vim.notify('mep.org: could not open ' .. file_part, vim.log.levels.WARN)
    return false
  end
  if locator then
    local new_buf = vim.api.nvim_get_current_buf()
    if locator:match('^%d+$') then
      pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(locator), 0 })
    elseif locator:sub(1, 1) == '*' then
      local lnum = M.find_by_title(new_buf, locator:sub(2), todo_keywords)
      if lnum then
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      end
    end
  end
  return true
end

--- Dispatch `target` (a link's raw target text) to the right handler:
--- a URL/mailto scheme opens via `open_url`; `id:`/`#custom-id` jump to
--- the headline with that property in `bufnr`; `file:` opens a file
--- (with an optional `::N`/`::*Heading` locator); `*Heading` jumps to a
--- same-buffer headline titled `Heading`; anything else first tries a
--- same-buffer heading-title search, then falls back to treating it as
--- a relative file path — real org-mode's own bare-target heuristic,
--- simplified (no fuzzy/regex text search). Returns true on success.
function M.open_target(bufnr, target, todo_keywords)
  if target:match('^%a[%w+.-]*://') or target:match('^mailto:') then
    return M.open_url(target)
  end
  if target:match('^id:') then
    local id = target:sub(4)
    local lnum = property.find_by(bufnr, 'ID', id)
    if lnum then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return true
    end
    vim.notify('mep.org: no headline with ID ' .. id, vim.log.levels.WARN)
    return false
  end
  if target:sub(1, 1) == '#' then
    local id = target:sub(2)
    local lnum = property.find_by(bufnr, 'CUSTOM_ID', id)
    if lnum then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return true
    end
    vim.notify('mep.org: no headline with CUSTOM_ID ' .. id, vim.log.levels.WARN)
    return false
  end
  if target:match('^file:') then
    return M.open_file(target:sub(6), todo_keywords)
  end
  if target:sub(1, 1) == '*' then
    local title = target:sub(2)
    local lnum = M.find_by_title(bufnr, title, todo_keywords)
    if lnum then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return true
    end
    vim.notify('mep.org: no headline titled ' .. title, vim.log.levels.WARN)
    return false
  end
  local lnum = M.find_by_title(bufnr, target, todo_keywords)
  if lnum then
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    return true
  end
  return M.open_file(target, todo_keywords)
end

--- Follow the link under the cursor in `win` (see `open_target` for how
--- the target is dispatched). Returns false (with a notification) if
--- there's no link under the cursor.
function M.follow(bufnr, win, todo_keywords)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local _, _, target = M.find_at_col(line, col)
  if not target then
    vim.notify('mep.org: no link under cursor', vim.log.levels.WARN)
    return false
  end
  return M.open_target(bufnr, target, todo_keywords)
end

--- Store a link to the headline containing `lnum` (real org-mode's
--- `org-store-link`) for later recall as `insert_interactive`'s default
--- target. Prefers the headline's own `:CUSTOM_ID:`, then `:ID:`, then
--- falls back to a `*Title` fuzzy-heading link. Only the single most
--- recently stored link is kept (not a history list, unlike real
--- org-mode). Returns the stored `{ target, description }`, or nil if
--- `lnum` isn't inside a headline.
function M.store_link(bufnr, lnum, todo_keywords)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local parsed = headline_mod.parse(line, todo_keywords or {})
  local custom_id = property.get(bufnr, at, 'CUSTOM_ID')
  local id = not custom_id and property.get(bufnr, at, 'ID')
  local target
  if custom_id then
    target = '#' .. custom_id
  elseif id then
    target = 'id:' .. id
  else
    target = '*' .. parsed.title
  end
  M.stored = { target = target, description = parsed.title }
  return M.stored
end

--- Insert a link, interactively, in `bufnr`/`win`. In visual mode (per
--- `vim.fn.mode()` at call time), the current charwise selection becomes
--- the description automatically (only the target is prompted for) and
--- the selection is replaced in place; other selection modes
--- (linewise/blockwise) aren't specially handled and fall through to
--- normal-mode behavior. Otherwise prompts for target then description
--- (empty means none) and inserts at the cursor. The target prompt
--- defaults to the most recently `store_link`-ed target, if any.
function M.insert_interactive(bufnr, win)
  local default_target = M.stored and M.stored.target or ''

  if vim.fn.mode() == 'v' then
    -- '</'> marks aren't finalized until visual mode is actually exited
    -- (confirmed empirically: getpos() returns all-zeros while still
    -- actively in visual mode) -- leave visual mode first so they're
    -- valid to read.
    vim.cmd('normal! \27')
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    local start_line, start_col = s[2], s[3] - 1
    local end_line, end_col = e[2], e[3]
    local seltext = table.concat(vim.api.nvim_buf_get_text(bufnr, start_line - 1, start_col, end_line - 1, end_col, {}), ' ')

    vim.ui.input({ prompt = 'Link target: ', default = default_target }, function(target)
      if not target or target == '' then
        return
      end
      local rendered = M.render({ target = target, description = seltext ~= '' and seltext or nil })
      vim.api.nvim_buf_set_text(bufnr, start_line - 1, start_col, end_line - 1, end_col, { rendered })
    end)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  vim.ui.input({ prompt = 'Link target: ', default = default_target }, function(target)
    if not target or target == '' then
      return
    end
    vim.ui.input({ prompt = 'Description (optional): ' }, function(description)
      local rendered = M.render({ target = target, description = description and description ~= '' and description or nil })
      local lnum, col = cursor[1], cursor[2]
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line:sub(1, col) .. rendered .. line:sub(col + 1) })
    end)
  end)
end

return M

--- Footnotes: `[fn:name]` references, `[fn:name:inline definition]` (a
--- reference and its definition combined at the point of use), and a
--- standalone `[fn:name] definition text` line (real org-mode lets a
--- definition's text continue onto following paragraphs; this project
--- reads/writes it as a single line, the same "narrow slice" tradeoff
--- mep.org.clock's :LOGBOOK: state-change notes made).
local M = {}

local INLINE_DEF = '%[fn:([%w_%-]*):([^%]]+)%]'
local PLAIN_REF = '%[fn:([%w_%-]+)%]'
local DEF_LINE = '^%[fn:([%w_%-]+)%]%s+(.*)$'

--- Find the first footnote construct in `line` at or after byte index
--- `init` (default 1): a plain reference `[fn:name]`, or an inline
--- definition `[fn:name:def]` (name may be empty for an anonymous inline
--- definition). Returns `start_col, end_col` (1-based, inclusive), `name`
--- (nil for anonymous), and `inline_def` (nil for a plain reference), or
--- nil if there isn't one.
function M.find(line, init)
  init = init or 1
  local s1, e1, n1, d1 = line:find(INLINE_DEF, init)
  local s2, e2, n2 = line:find(PLAIN_REF, init)
  -- an inline-def match always starts no later than a plain-ref match
  -- that begins at the same position (PLAIN_REF can't match past the
  -- colon an inline def introduces), so prefer the earlier start; on a
  -- tie prefer the inline def, since PLAIN_REF's `%]` there would just be
  -- matching into the middle of the def text.
  if s1 and (not s2 or s1 <= s2) then
    return s1, e1, (n1 ~= '' and n1 or nil), d1
  elseif s2 then
    return s2, e2, n2, nil
  end
  return nil
end

--- Every footnote *definition* line in `lines` (a plain list of buffer
--- lines): a list of `{ lnum, name, text }`, in document order. A
--- definition line must start at column 0, matching real org-mode.
function M.find_definitions(lines)
  local defs = {}
  for i, line in ipairs(lines) do
    local name, text = line:match(DEF_LINE)
    if name then
      defs[#defs + 1] = { lnum = i, name = name, text = text }
    end
  end
  return defs
end

--- The line number of the definition of footnote `name` in `bufnr`, or
--- nil.
function M.find_definition(bufnr, name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, def in ipairs(M.find_definitions(lines)) do
    if def.name == name then
      return def.lnum
    end
  end
  return nil
end

--- The line number of the first reference (plain or inline-def) to
--- footnote `name` in `bufnr`, or nil.
function M.find_reference(bufnr, name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local init = 1
    while true do
      local s, _, found_name = M.find(line, init)
      if not s then
        break
      end
      if found_name == name then
        return i
      end
      init = s + 1
    end
  end
  return nil
end

--- Whether the cursor in `win` sits on a footnote definition line
--- (`'def', name`), a named reference (`'ref', name`), or neither
--- (nil). An anonymous inline definition (`[fn::text]`, no name) counts
--- as neither, since it has no separate counterpart to navigate to.
local function what_at_cursor(bufnr, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''

  local def_name = line:match(DEF_LINE)
  if def_name then
    return 'def', def_name
  end

  local init = 1
  while true do
    local s, e, name = M.find(line, init)
    if not s then
      return nil
    end
    if col >= s - 1 and col < e and name then
      return 'ref', name
    end
    init = e and e + 1 or s + 1
  end
end

--- Whether the cursor in `win` is on either half of a footnote (a
--- definition line, or a named reference) — used to decide whether
--- `<C-c><C-x>f` should navigate or insert a new footnote instead,
--- without `goto_counterpart`'s own "nothing here" notification firing
--- for what's actually the normal "insert a new one" case.
function M.at_cursor(bufnr, win)
  return what_at_cursor(bufnr, win) ~= nil
end

--- Jump from a footnote reference under the cursor to its definition, or
--- from a definition line back to its first reference (real org-mode's
--- context-sensitive `org-footnote-action` navigation half). Returns
--- true on success, false (with a notification) if the cursor isn't on
--- either half of a footnote, or its counterpart can't be found.
function M.goto_counterpart(bufnr, win)
  local kind, name = what_at_cursor(bufnr, win)

  if kind == 'def' then
    local target = M.find_reference(bufnr, name)
    if target then
      vim.api.nvim_win_set_cursor(win, { target, 0 })
      return true
    end
    vim.notify('mep.org: no reference to footnote ' .. name, vim.log.levels.WARN)
    return false
  end

  if kind == 'ref' then
    local target = M.find_definition(bufnr, name)
    if target then
      vim.api.nvim_win_set_cursor(win, { target, 0 })
      return true
    end
    vim.notify('mep.org: no definition for footnote ' .. name, vim.log.levels.WARN)
    return false
  end

  vim.notify('mep.org: no footnote under cursor', vim.log.levels.WARN)
  return false
end

--- The next unused numeric footnote name ("1", "2", ...) in `bufnr`,
--- for auto-naming an anonymous new footnote (real org-mode does the
--- same for `[fn:N]`-shaped names).
local function next_auto_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local max = 0
  local scan = function(name)
    local n = tonumber(name)
    if n and n > max then
      max = n
    end
  end
  for _, def in ipairs(M.find_definitions(lines)) do
    scan(def.name)
  end
  for _, line in ipairs(lines) do
    local init = 1
    while true do
      local s, e, name = M.find(line, init)
      if not s then
        break
      end
      if name then
        scan(name)
      end
      init = e + 1
    end
  end
  return tostring(max + 1)
end

--- Insert a new footnote reference at the cursor and append its
--- definition, interactively: prompts for a name (blank auto-numbers,
--- real org-mode's own convention) then definition text via
--- `vim.ui.input`. The reference `[fn:name]` is inserted at the cursor;
--- the definition `[fn:name] text` is appended as a new line directly
--- after the last existing footnote-definition line, or at the end of
--- the buffer if there are none yet — grouping definitions together,
--- matching real org-mode's own "footnotes section" convention.
function M.insert_interactive(bufnr, win)
  vim.ui.input({ prompt = 'Footnote name (blank to auto-number): ' }, function(name)
    if name == nil then
      return
    end
    if name == '' then
      name = next_auto_name(bufnr)
    end
    vim.ui.input({ prompt = 'Footnote definition: ' }, function(text)
      if not text or text == '' then
        return
      end
      local cursor = vim.api.nvim_win_get_cursor(win)
      local lnum, col = cursor[1], cursor[2]
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
      local ref = '[fn:' .. name .. ']'
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line:sub(1, col) .. ref .. line:sub(col + 1) })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local defs = M.find_definitions(lines)
      local insert_at = #lines
      if #defs > 0 then
        insert_at = defs[#defs].lnum
      end
      vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { '[fn:' .. name .. '] ' .. text })
    end)
  end)
end

return M

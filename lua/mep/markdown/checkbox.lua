--- GFM task-list checkboxes (`- [ ]`/`- [x]`, and their numbered-list
--- equivalent `1. [ ]`/`1. [x]`) — mirrors `mep.org.checkbox`, broadened
--- to also match an ordered-list marker since GFM task lists commonly
--- appear in both bullet and numbered lists (real org-mode checkboxes
--- only ever sit in plain lists, so `mep.org.checkbox` doesn't need
--- that second pattern).
local M = {}

local PATTERNS = {
  '^(%s*[-+*]%s+)%[([ xX])%](.*)$',
  '^(%s*%d+[.)]%s+)%[([ xX])%](.*)$',
}

local function match_checkbox(line)
  for _, pattern in ipairs(PATTERNS) do
    local prefix, mark, rest = line:match(pattern)
    if prefix then
      return prefix, mark, rest
    end
  end
  return nil
end

--- Whether `line` is a checkbox list item.
function M.is_checkbox(line)
  return match_checkbox(line) ~= nil
end

--- Whether a checkbox line is checked. Returns nil (not true/false) if
--- `line` isn't a checkbox line at all.
function M.is_checked(line)
  local _, mark = match_checkbox(line)
  if not mark then
    return nil
  end
  return mark ~= ' '
end

--- Toggle the checkbox on `lnum` in `bufnr` between checked/unchecked.
--- Returns the new checked state (boolean), or nil if `lnum` isn't a
--- checkbox line.
function M.toggle(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then
    return nil
  end
  local prefix, mark, rest = match_checkbox(line)
  if not prefix then
    return nil
  end
  local was_checked = mark ~= ' '
  local new_mark = was_checked and ' ' or 'x'
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { prefix .. '[' .. new_mark .. ']' .. rest })
  return not was_checked
end

return M

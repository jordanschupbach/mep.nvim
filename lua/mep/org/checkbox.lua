local M = {}

local CHECKBOX_PATTERN = '^(%s*[-+*]%s+)%[([ xX])%](.*)$'

--- Whether `line` is a checkbox list item ("- [ ] ..." / "- [x] ...").
function M.is_checkbox(line)
  return line:match(CHECKBOX_PATTERN) ~= nil
end

--- Whether a checkbox line is checked. Returns nil (not true/false) if
--- `line` isn't a checkbox line at all — mep.org.statistics relies on
--- that three-way result to skip non-checkbox lines when counting.
function M.is_checked(line)
  local _, mark = line:match(CHECKBOX_PATTERN)
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
  local prefix, mark, rest = line:match(CHECKBOX_PATTERN)
  if not prefix then
    return nil
  end
  local was_checked = mark ~= ' '
  local new_mark = was_checked and ' ' or 'X'
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { prefix .. '[' .. new_mark .. ']' .. rest })
  return not was_checked
end

return M

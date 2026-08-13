--- "Easy templates": typing `<s` then a trigger key expands to a
--- `#+begin_src` / `#+end_src` block (and similarly for a handful of
--- other common block types). Real org-mode's trigger is Tab; the
--- keymap wiring (which key, and falling back to normal Tab behavior
--- when the pattern doesn't match) lives in org.lua — this module is
--- just the pure "does the text before the cursor match a trigger, and
--- if so what does it expand to" logic.
local M = {}

M.templates = {
  s = 'src',
  e = 'example',
  q = 'quote',
  c = 'center',
  v = 'verse',
  C = 'comment',
}

--- If the text from the start of the current line up to the cursor is
--- (optional indent) + "<" + a known template key, replace it with the
--- corresponding `#+begin_X` / `#+end_X` block and leave the cursor on
--- the blank line in between. Returns true if it expanded something,
--- false (buffer untouched) if the text didn't match any trigger —
--- callers should fall back to normal Tab behavior in that case.
function M.expand_at_cursor(bufnr, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local before = line:sub(1, col)

  local indent, key = before:match('^(%s*)<(%a)$')
  local name = key and M.templates[key]
  if not name then
    return false
  end

  local after = line:sub(col + 1)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, {
    indent .. '#+begin_' .. name,
    indent,
    indent .. '#+end_' .. name .. after,
  })
  vim.api.nvim_win_set_cursor(win, { lnum + 1, #indent })
  return true
end

return M

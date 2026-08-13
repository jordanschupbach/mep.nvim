--- Generic `#+BEGIN_<kind> ... #+END_<kind>` special blocks — quote,
--- verse, example, center, and anything else shaped like one (including
--- src, though mep.org.babel owns execution/tangling of those; parsing
--- them here too is harmless, just unused by babel). Pure line-pattern
--- parsing, same style as mep.org.babel.find_blocks, generalized to any
--- block name instead of hard-coding "src". Highlighting already treats
--- any such block as one opaque span generically (queries/org/highlights.scm)
--- — this module is about *semantic* handling (mep.org.export's backends
--- render quote/verse/example/center differently from a plain paragraph).
local M = {}

local BEGIN_PATTERN = '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_(%a+)%s*(.-)%s*$'

--- Every `#+begin_<kind> ... #+end_<kind>` block in `lines` (a plain list
--- of buffer lines, e.g. from `vim.api.nvim_buf_get_lines`): a list of
--- `{ kind (lower-cased), start_lnum, end_lnum, args, body }` (1-indexed,
--- inclusive; `body` is the list of lines strictly between the
--- delimiters). `kind` must match between BEGIN/END case-insensitively,
--- matching real org-mode; a block missing its matching END is skipped,
--- same as babel.find_blocks.
function M.find_blocks(lines)
  local blocks = {}
  local i = 1
  while i <= #lines do
    local kind, args = lines[i]:match(BEGIN_PATTERN)
    if kind then
      local kind_lower = kind:lower()
      local end_pattern = '^%s*#%+end_' .. kind_lower .. '%s*$'
      local body = {}
      local j = i + 1
      while j <= #lines and not lines[j]:lower():match(end_pattern) do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if j <= #lines then
        blocks[#blocks + 1] = { kind = kind_lower, start_lnum = i, end_lnum = j, args = args, body = body }
        i = j + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return blocks
end

--- The block containing `lnum` (cursor anywhere from `#+begin_<kind>`
--- through `#+end_<kind>`, inclusive) in `lines`, or nil.
function M.at(lines, lnum)
  for _, block in ipairs(M.find_blocks(lines)) do
    if lnum >= block.start_lnum and lnum <= block.end_lnum then
      return block
    end
  end
  return nil
end

return M

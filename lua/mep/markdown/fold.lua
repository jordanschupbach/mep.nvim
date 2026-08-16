--- ATX-heading-depth-based folding for markdown buffers — mirrors
--- `mep.org.fold`: a heading's fold swallows its body text and every
--- shallower-nested heading's own content as one block, and a fenced
--- (``` / ~~~) code block gets its own nested fold one level deeper
--- than its enclosing heading, foldable independently of the rest of
--- its section (real org-mode's own `#+begin_src` treatment, mirrored
--- here for GFM fences).
local M = {}

local function heading_level(line)
  local hashes = line:match('^(#+)%s')
  if not hashes or #hashes > 6 then
    return nil
  end
  return #hashes
end

local function is_fence(line)
  return line:match('^%s*```') ~= nil or line:match('^%s*~~~') ~= nil
end

--- Every fenced code block's own line range in `bufnr`: `{ start_lnum,
--- end_lnum }` pairs (1-indexed, inclusive). A fence still open at
--- end-of-buffer extends through the last line.
local function fence_regions(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local regions = {}
  local open_at = nil
  for i, line in ipairs(lines) do
    if open_at then
      if is_fence(line) then
        regions[#regions + 1] = { start_lnum = open_at, end_lnum = i }
        open_at = nil
      end
    elseif is_fence(line) then
      open_at = i
    end
  end
  if open_at then
    regions[#regions + 1] = { start_lnum = open_at, end_lnum = #lines }
  end
  return regions
end

--- 'foldexpr' for markdown buffers, called by Vim once per line with the
--- line number in `vim.v.lnum`. Wire up with:
---   vim.wo[win].foldmethod = 'expr'
---   vim.wo[win].foldexpr = "v:lua.require'mep.markdown.fold'.foldexpr()"
function M.foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)

  local level = heading_level(line)
  if level then
    return '>' .. tostring(level)
  end

  local base_level = 0
  for i = lnum - 1, 1, -1 do
    local hl = heading_level(vim.fn.getline(i))
    if hl then
      base_level = hl
      break
    end
  end

  for _, region in ipairs(fence_regions(vim.api.nvim_get_current_buf())) do
    if lnum >= region.start_lnum and lnum <= region.end_lnum then
      if lnum == region.start_lnum then
        return '>' .. tostring(base_level + 1)
      end
      return base_level + 1
    end
  end

  return base_level -- nothing above any heading yet: not folded
end

return M

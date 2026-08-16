--- Headline-depth-based folding for org buffers. Deliberately not the
--- same as generic treesitter folding (`vim.treesitter.foldexpr`, which
--- mep.treesitter can also turn on): org's actual fold unit is the
--- headline subtree, not every syntax node, so a heading's fold should
--- swallow its body text and child headlines as one block regardless of
--- what's syntactically inside them.
---
--- A `#+begin_src ... #+end_src` block additionally gets its own nested
--- fold, one level deeper than its enclosing headline, so it can be
--- collapsed on its own (`za` on the block) without collapsing the rest
--- of the section — real org-mode's own `#+begin_src` blocks are
--- independently foldable the same way. Any contiguous `# comment` line
--- (or lines) directly above the block are pulled into that same fold,
--- so a comment introducing a block collapses along with it rather than
--- being left dangling above a folded-away block.
local headline = require('mep.org.headline')
local babel = require('mep.org.babel')

local M = {}

local COMMENT_PATTERN = '^%s*#%s'
local BARE_COMMENT_PATTERN = '^%s*#$'

--- Whether `line` is a plain org comment (`# ...` or a bare `#`) — not a
--- `#+` directive/affiliated-keyword line, which this deliberately
--- leaves alone (org-mode itself treats those as a different construct).
local function is_comment(line)
  return line:match(COMMENT_PATTERN) ~= nil or line:match(BARE_COMMENT_PATTERN) ~= nil
end

--- `block.start_lnum` extended upward over any contiguous comment lines
--- directly above it (no blank-line tolerance — a blank line between a
--- comment and the block it's introducing would just be a paragraph
--- break, not related to this block).
local function block_fold_start(bufnr, start_lnum)
  local fold_start = start_lnum
  local lnum = start_lnum - 1
  while lnum >= 1 do
    local line = (vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false))[1]
    if not line or not is_comment(line) then
      break
    end
    fold_start = lnum
    lnum = lnum - 1
  end
  return fold_start
end

--- Every `#+begin_src ... #+end_src` block's own fold region in
--- `bufnr`: `{ start_lnum, end_lnum }` pairs (1-indexed, inclusive),
--- `start_lnum` extended per `block_fold_start` above.
local function block_fold_regions(bufnr)
  local regions = {}
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    regions[#regions + 1] = { start_lnum = block_fold_start(bufnr, block.start_lnum), end_lnum = block.end_lnum }
  end
  return regions
end

--- 'foldexpr' for org buffers, called by Vim once per line with the line
--- number in `vim.v.lnum`. A headline starts a new fold at its star
--- depth (so consecutive same-level headlines don't merge into one
--- fold); any other line inherits the nearest enclosing headline's
--- depth, except a src block (and its own preceding comment lines, see
--- `block_fold_regions`), which nests one level deeper so it can fold
--- independently of the rest of its section. Wire up with:
---   vim.wo[win].foldmethod = 'expr'
---   vim.wo[win].foldexpr = "v:lua.require'mep.org.fold'.foldexpr()"
function M.foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)

  if headline.is_headline(line) then
    return '>' .. tostring(#(line:match('^(%*+)')))
  end

  local base_level = 0
  for i = lnum - 1, 1, -1 do
    local l = vim.fn.getline(i)
    if headline.is_headline(l) then
      base_level = #(l:match('^(%*+)'))
      break
    end
  end

  for _, region in ipairs(block_fold_regions(vim.api.nvim_get_current_buf())) do
    if lnum >= region.start_lnum and lnum <= region.end_lnum then
      if lnum == region.start_lnum then
        return '>' .. tostring(base_level + 1)
      end
      return base_level + 1
    end
  end

  return base_level -- nothing above any headline yet: not folded
end

return M

--- Headline-depth-based folding for org buffers. Deliberately not the
--- same as generic treesitter folding (`vim.treesitter.foldexpr`, which
--- mep.treesitter can also turn on): org's actual fold unit is the
--- headline subtree, not every syntax node, so a heading's fold should
--- swallow its body text and child headlines as one block regardless of
--- what's syntactically inside them.
local headline = require('mep.org.headline')

local M = {}

--- 'foldexpr' for org buffers, called by Vim once per line with the line
--- number in `vim.v.lnum`. A headline starts a new fold at its star
--- depth (so consecutive same-level headlines don't merge into one
--- fold); any other line inherits the nearest enclosing headline's
--- depth. Wire up with:
---   vim.wo[win].foldmethod = 'expr'
---   vim.wo[win].foldexpr = "v:lua.require'mep.org.fold'.foldexpr()"
function M.foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)

  if headline.is_headline(line) then
    return '>' .. tostring(#(line:match('^(%*+)')))
  end

  for i = lnum - 1, 1, -1 do
    local l = vim.fn.getline(i)
    if headline.is_headline(l) then
      return #(l:match('^(%*+)'))
    end
  end

  return 0 -- nothing above any headline yet: not folded
end

return M

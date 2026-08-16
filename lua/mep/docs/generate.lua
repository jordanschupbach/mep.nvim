--- Docstring-skeleton insertion: `mep.docs.lsp`'s structured signature
--- help when a client is attached and answers, `mep.docs.parser`'s
--- regex fallback (scanning the cursor's own line) otherwise.
local templates = require('mep.docs.templates')
local parser = require('mep.docs.parser')
local lsp = require('mep.docs.lsp')

local M = {}

--- One indentation level, in `bufnr`'s own configured style (spaces per
--- `'shiftwidth'`/`'tabstop'` when `'expandtab'` is set, a literal tab
--- otherwise) — used to nest a `'below'`-position skeleton one level
--- deeper than its function line, the way a real docstring sits inside
--- the function body.
local function indent_unit(bufnr)
  if vim.bo[bufnr].expandtab then
    local width = vim.bo[bufnr].shiftwidth
    if width == 0 then
      width = vim.bo[bufnr].tabstop
    end
    return string.rep(' ', width > 0 and width or 4)
  end
  return '\t'
end

--- Insert `style.render(name, params)`'s lines into `bufnr` at `lnum`
--- (1-based, the function's own line), indented to match — `'above'`
--- shares that line's own indentation; `'below'` nests one level deeper
--- (Python's own convention: the docstring is the body's first
--- statement).
local function insert_skeleton(bufnr, lnum, line, style, name, params)
  local base_indent = line:match('^%s*') or ''
  local skeleton_indent = (style.position == 'below') and (base_indent .. indent_unit(bufnr)) or base_indent
  local skeleton = style.render(name, params or {})

  local indented = {}
  for i, l in ipairs(skeleton) do
    indented[i] = (l == '') and '' or (skeleton_indent .. l)
  end

  local insert_at = (style.position == 'below') and lnum or (lnum - 1)
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, indented)
end

--- Insert a doc-comment skeleton for the function on `win`'s cursor
--- line in `bufnr`: `mep.docs.lsp.request` first, falling back to
--- `mep.docs.parser.parse` on that same line if no client answers.
--- Notifies (no-op) when `bufnr`'s filetype has no curated docstring
--- template at all, or neither path finds a function signature there.
function M.generate(bufnr, win)
  local filetype = vim.bo[bufnr].filetype
  local style = templates.docstring[filetype]
  if not style then
    vim.notify('mep.docs: no docstring template for filetype "' .. filetype .. '"', vim.log.levels.WARN)
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''

  lsp.request(bufnr, win, function(name, params)
    if not name then
      name, params = parser.parse(line, filetype)
    end
    if not name then
      vim.notify('mep.docs: no function signature detected on this line', vim.log.levels.WARN)
      return
    end
    insert_skeleton(bufnr, lnum, line, style, name, params)
  end)
end

return M

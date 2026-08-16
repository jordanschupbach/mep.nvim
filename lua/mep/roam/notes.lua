--- Note discovery/title/ID resolution: reuses `mep.org.id.get_or_create`
--- for stable per-note IDs (this project's own single ID mechanism, no
--- separate one for roam) — anchored on each note file's *first*
--- headline, since `mep.org.id`/`mep.org.property` are headline-scoped
--- (there's no file-level `:ID:` concept to hang one off otherwise). A
--- note file with no headline at all has nothing to anchor an ID on and
--- is skipped everywhere in this library.
local headline_mod = require('mep.org.headline')
local id_mod = require('mep.org.id')

local M = {}

--- Load `path` into a buffer without displaying it, reusing an
--- already-open buffer's live content if there is one — the same idiom
--- `mep.org.agenda`'s own (private) `load_buf` helper uses.
local function load_buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end
M.load_buf = load_buf

--- The line number of the first headline in `bufnr`, or nil.
local function first_headline(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if headline_mod.is_headline(line) then
      return i
    end
  end
  return nil
end
M.first_headline = first_headline

--- `bufnr`'s own note title: its `#+TITLE:` file keyword if present
--- (checked over the first 30 lines — real org file-keyword position),
--- else its first headline's own title, else the bare filename.
function M.title(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(30, vim.api.nvim_buf_line_count(bufnr)), false)
  for _, line in ipairs(lines) do
    local title = line:match('^#%+TITLE:%s*(.-)%s*$')
    if title then
      return title
    end
  end
  local lnum = first_headline(bufnr)
  if lnum then
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
    return headline_mod.parse(line, {}).title
  end
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t:r')
end

--- `bufnr`'s own note ID: `mep.org.id.get_or_create` on its first
--- headline (creating the `:ID:` property, and the drawer itself, if
--- neither exists yet — same "assign on first sync" behavior real
--- org-roam's own database sync has). nil if the file has no headline
--- to anchor an ID on.
function M.id(bufnr)
  local lnum = first_headline(bufnr)
  if not lnum then
    return nil
  end
  return id_mod.get_or_create(bufnr, lnum)
end

--- Every `.org` file recursively under any of `roam_dirs`, deduped and
--- sorted.
function M.files(roam_dirs)
  local seen = {}
  local out = {}
  for _, dir in ipairs(roam_dirs or {}) do
    for _, path in ipairs(vim.fn.glob(vim.fn.expand(dir) .. '/**/*.org', false, true)) do
      if not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  table.sort(out)
  return out
end

--- Every note across `roam_dirs`: `{ path, bufnr, title, id }`, sorted
--- by title. A file with no headline (so no ID to link to) is skipped.
function M.list(roam_dirs)
  local out = {}
  for _, path in ipairs(M.files(roam_dirs)) do
    local bufnr = load_buf(path)
    local id = M.id(bufnr)
    if id then
      out[#out + 1] = { path = path, bufnr = bufnr, title = M.title(bufnr), id = id }
    end
  end
  table.sort(out, function(a, b)
    return a.title < b.title
  end)
  return out
end

return M

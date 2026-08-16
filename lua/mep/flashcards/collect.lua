--- Finds every `:drill:`-tagged (configurably) headline across a set of
--- files — `mep.org.agenda.files` for glob resolution (the same
--- `drill_files`/`agenda_files` shape), `mep.org.tags.effective_tags`
--- for inheritance-aware tag matching, the same "reflects live, unsaved
--- buffer content" load idiom `mep.org.agenda`'s own `collect_entries`
--- uses.
local agenda = require('mep.org.agenda')
local headline = require('mep.org.headline')
local tags_mod = require('mep.org.tags')
local state_mod = require('mep.flashcards.state')

local M = {}

--- Load `path` into a buffer without displaying it, reusing an
--- already-open buffer's live content if there is one — `mep.org.
--- agenda`'s own (private) `load_buf` helper, duplicated rather than
--- exported since it's three lines and this is the only other place
--- that needs it.
local function load_buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end

--- Every `tag`-tagged headline in `bufnr`: `{ bufnr, file, lnum, title,
--- state }` (`state` is `mep.flashcards.state.read`'s own shape).
local function collect_from_buffer(bufnr, path, tag)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = {}
  for i, line in ipairs(lines) do
    if headline.is_headline(line) then
      local effective = tags_mod.effective_tags(bufnr, i)
      if vim.tbl_contains(effective, tag) then
        local parsed = headline.parse(line, {})
        entries[#entries + 1] = {
          bufnr = bufnr,
          file = path,
          lnum = i,
          title = parsed.title,
          state = state_mod.read(bufnr, i),
        }
      end
    end
  end
  return entries
end

--- Every `tag`-tagged headline across `drill_files` (see `mep.org.
--- agenda.files` for the literal-path/glob-pattern shape).
function M.entries(drill_files, tag)
  local out = {}
  for _, path in ipairs(agenda.files(drill_files)) do
    vim.list_extend(out, collect_from_buffer(load_buf(path), path, tag))
  end
  return out
end

--- Just the entries from `M.entries` that are due today (`mep.
--- flashcards.state.is_due`), in the same (file, then document) order.
function M.due_entries(drill_files, tag, today)
  local due = {}
  for _, entry in ipairs(M.entries(drill_files, tag)) do
    if state_mod.is_due(entry.state, today) then
      due[#due + 1] = entry
    end
  end
  return due
end

return M

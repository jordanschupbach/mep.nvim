--- Finds every note that links (via a `[[id:...]]` link, real org-mode
--- `id:` targets — `mep.org.link.find`'s own parsing, reused rather than
--- a separate link scanner) to a given note ID — the backlinks half of
--- `mep.roam`.
local link_mod = require('mep.org.link')
local headline_mod = require('mep.org.headline')
local outline = require('mep.org.outline')
local notes = require('mep.roam.notes')

local M = {}

--- Every headline in `bufnr` that links to `id`, one entry per
--- *headline* (not per link — several links to the same ID under one
--- headline still count once): `{ lnum, title }`. A link doesn't have
--- to sit directly on a headline line itself (it's often in body
--- prose); each match is attributed to its *nearest enclosing*
--- headline (`mep.org.outline.current_headline`) — real org-roam's own
--- notion of "which note/section links here".
local function links_to(bufnr, id)
  local target = 'id:' .. id
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  local seen = {}
  for i, line in ipairs(lines) do
    local init = 1
    while true do
      local s, e, link_target = link_mod.find(line, init)
      if not s then
        break
      end
      if link_target == target then
        local headline_lnum = outline.current_headline(bufnr, i) or i
        if not seen[headline_lnum] then
          seen[headline_lnum] = true
          local hline = vim.api.nvim_buf_get_lines(bufnr, headline_lnum - 1, headline_lnum, false)[1]
          local title = (hline and headline_mod.is_headline(hline)) and headline_mod.parse(hline, {}).title
            or notes.title(bufnr)
          out[#out + 1] = { lnum = headline_lnum, title = title }
        end
      end
      init = e + 1
    end
  end
  return out
end

--- Every note across `roam_dirs` that links to `id`: `{ path, bufnr,
--- lnum, title }` entries, sorted by path then line.
function M.find_backlinks(roam_dirs, id)
  local out = {}
  for _, path in ipairs(notes.files(roam_dirs)) do
    local bufnr = notes.load_buf(path)
    for _, entry in ipairs(links_to(bufnr, id)) do
      out[#out + 1] = { path = path, bufnr = bufnr, lnum = entry.lnum, title = entry.title }
    end
  end
  table.sort(out, function(a, b)
    if a.path ~= b.path then
      return a.path < b.path
    end
    return a.lnum < b.lnum
  end)
  return out
end

return M

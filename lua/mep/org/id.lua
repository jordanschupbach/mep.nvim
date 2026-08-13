--- org-id: generate/lookup unique `:ID:` properties on headlines, for
--- stable cross-file links independent of title text (`mep.org.link`
--- already knows how to *follow* an `id:` target — this module is about
--- *creating* and finding one). No cross-file ID index: `find` only
--- searches the one buffer given, the same single-buffer scope
--- `mep.org.refile` documents for cross-file work waiting on a future
--- phase.
local outline = require('mep.org.outline')
local property = require('mep.org.property')

local M = {}

--- A random RFC-4122-shaped v4 UUID string ("xxxxxxxx-xxxx-4xxx-yxxx-
--- xxxxxxxxxxxx"), matching real org-id's own default `org-id-method`.
--- Not cryptographically secure — good enough for "collision-astronomically-
--- unlikely link anchor", not a security token.
function M.generate()
  math.randomseed(vim.uv and vim.uv.hrtime() or os.clock() * 1e9)
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (template:gsub('[xy]', function(c)
    local r = math.random(0, 15)
    local v = (c == 'x') and r or (r % 4 + 8)
    return string.format('%x', v)
  end))
end

--- The `:ID:` property of the headline containing `lnum`, creating and
--- setting one (via `generate`) if it doesn't already have one. Returns
--- the ID, or nil if `lnum` isn't inside a headline.
function M.get_or_create(bufnr, lnum)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  local existing = property.get(bufnr, at, 'ID')
  if existing then
    return existing
  end
  local id = M.generate()
  property.set(bufnr, at, 'ID', id)
  return id
end

--- The line number of the headline in `bufnr` whose `:ID:` property is
--- `id`, or nil.
function M.find(bufnr, id)
  return property.find_by(bufnr, 'ID', id)
end

--- `get_or_create` on the headline containing `lnum`, notifying the
--- resulting ID (real org-mode's `org-id-get-create`).
function M.get_or_create_interactive(bufnr, lnum)
  local id = M.get_or_create(bufnr, lnum)
  if id then
    vim.notify('mep.org: ID ' .. id, vim.log.levels.INFO)
  end
  return id
end

return M

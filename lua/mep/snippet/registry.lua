--- Per-filetype snippet storage — plain Lua tables, no textmate/VSCode
--- JSON loading. Pure bookkeeping, no expansion/navigation logic of its
--- own (that's `mep.snippet.session`).
local M = {}

-- filetype -> list of { trigger, body }
local snippets = {}

--- Register `list` (each `{ trigger, body }`) under `filetype`.
--- Additive — call again to add more, e.g. from separate ftplugin-style
--- setup calls.
function M.add(filetype, list)
  snippets[filetype] = snippets[filetype] or {}
  local bucket = snippets[filetype]
  for _, snip in ipairs(list) do
    bucket[#bucket + 1] = snip
  end
end

--- Every snippet registered for `filetype` (empty list if none).
function M.get(filetype)
  return snippets[filetype] or {}
end

--- The snippet registered for `trigger` under `filetype`, or nil.
--- Last-added wins on a duplicate trigger within the same filetype.
function M.find(filetype, trigger)
  local found
  for _, snip in ipairs(M.get(filetype)) do
    if snip.trigger == trigger then
      found = snip
    end
  end
  return found
end

--- Test/dev-only: forget every registered snippet.
function M._reset()
  snippets = {}
end

return M

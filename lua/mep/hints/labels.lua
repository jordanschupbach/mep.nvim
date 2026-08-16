--- Pure label assignment for mep.hints: turns a target count into a list
--- of unique, short strings drawn from a configured charset, with no
--- knowledge of buffers/windows/extmarks at all.
local M = {}

--- Split `charset` into its individual characters, UTF-8-aware
--- (`vim.fn.strchars`/`strcharpart`, not byte-indexing) so a multi-byte
--- label glyph in a user's own charset still works.
local function chars(charset)
  local n = vim.fn.strchars(charset)
  local out = {}
  for i = 0, n - 1 do
    out[#out + 1] = vim.fn.strcharpart(charset, i, 1)
  end
  return out
end
M.chars = chars

--- `count` labels drawn from `charset`: single characters if `count`
--- fits within the charset, otherwise two-character combinations (first
--- char x second char, in charset order) — never a mix of the two, so a
--- pressed key is never ambiguous between "this is a whole label" and
--- "this is the first half of a longer one". If `count` exceeds
--- `#charset + #charset^2`, the returned list is shorter than `count`
--- (whatever's left over just doesn't get a reachable label — the same
--- graceful-degrade-rather-than-error posture as the rest of this
--- project, and not a realistic ceiling for one visible window).
function M.assign(count, charset)
  local cs = chars(charset)
  local labels = {}
  if count <= #cs then
    for i = 1, count do
      labels[i] = cs[i]
    end
    return labels
  end
  for i = 1, #cs do
    for j = 1, #cs do
      if #labels >= count then
        return labels
      end
      labels[#labels + 1] = cs[i] .. cs[j]
    end
  end
  return labels
end

return M

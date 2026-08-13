--- Tag match expressions: `+tag` (must have), `-tag` (must not have),
--- implicit AND by concatenation (`+work+urgent`), `|` for OR
--- (`+work|+home`) — AND binds tighter than OR, so `+a+b|+c` means
--- `(a AND b) OR c`, matching real org-mode. A filter predicate, meant
--- to be shared by sparse-tree search (Phase 6) and agenda (Phase 7) —
--- doesn't touch buffers at all, just evaluates against a tag list (e.g.
--- from mep.org.tags.effective_tags).
---
--- Deliberately simpler than real org-mode's match syntax: no
--- parentheses/grouping, and no TODO-state or property terms mixed in
--- (`+work/TODO`) — tags only, matching this phase's actual scope.
local M = {}

--- Parse a match expression into OR-groups, each an AND-list of
--- `{ tag, negate }`. Returns nil if `expr` has no valid terms at all
--- (empty string, or nothing but junk/whitespace).
function M.parse(expr)
  local groups = {}
  for group_text in (expr .. '|'):gmatch('([^|]*)|') do
    local terms = {}
    for sign, tag in group_text:gmatch('([%+%-])([%w_@]+)') do
      terms[#terms + 1] = { tag = tag, negate = sign == '-' }
    end
    if #terms > 0 then
      groups[#groups + 1] = terms
    end
  end
  if #groups == 0 then
    return nil
  end
  return groups
end

--- Whether `tags` (a plain list of tag strings) satisfies parsed match
--- `groups` (from `parse`): true if any OR-group has every one of its
--- AND-terms satisfied (`+tag` present, `-tag` absent).
function M.matches(groups, tags)
  local set = {}
  for _, t in ipairs(tags) do
    set[t] = true
  end
  for _, terms in ipairs(groups) do
    local ok = true
    for _, term in ipairs(terms) do
      if term.negate == (set[term.tag] == true) then
        ok = false
        break
      end
    end
    if ok then
      return true
    end
  end
  return false
end

--- Parse `expr` and test it against `tags` in one call. Returns false
--- (never errors) for a malformed/empty expression.
function M.eval(expr, tags)
  local groups = M.parse(expr)
  if not groups then
    return false
  end
  return M.matches(groups, tags)
end

return M

--- Pure keymap-introspection logic: no popup, no execution, just "what's
--- bound under this prefix, grouped by next key" — the part of
--- mep.whichkey that's cheaply unit-testable against real `vim.keymap.
--- set` calls, no floating window involved.
---
--- Works entirely in *raw* keycode bytes (`lhsraw`, as returned by
--- `nvim_get_keymap`/`nvim_buf_get_keymap`, and as produced by
--- `nvim_replace_termcodes(human, true, true, true)`) rather than
--- printable `<...>` notation — `lhs` itself is already
--- `keytrans()`-formatted in modern Neovim and its casing doesn't
--- reliably round-trip back through `nvim_replace_termcodes` (`<C-C>`
--- vs. the `<C-c>` a caller actually typed), so raw bytes are the only
--- representation both sides can agree on byte-for-byte. Human notation
--- only comes back in via `vim.fn.keytrans()`, and only for grouping/
--- display — a special key's raw form is always `K_SPECIAL`-prefixed
--- (0x80), which never collides with a plain/UTF-8 character's leading
--- byte, so byte-prefix matching lines up with key-token boundaries
--- with no ambiguity.
local M = {}

--- Every keymap for `mode` visible from `bufnr`: buffer-local entries
--- first, then global ones for any `lhsraw` a buffer-local mapping
--- doesn't already shadow — matching Neovim's own resolution order.
function M.all(mode, bufnr)
  bufnr = bufnr or 0
  local seen = {}
  local combined = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    seen[m.lhsraw] = true
    combined[#combined + 1] = m
  end
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if not seen[m.lhsraw] then
      combined[#combined + 1] = m
    end
  end
  return combined
end

--- Split human key notation `text` (as from `vim.fn.keytrans`) into an
--- ordered list of single-key tokens: each is either a bracketed
--- `<...>` token or one (possibly multi-byte UTF-8) character.
function M.tokenize(text)
  local tokens = {}
  local i = 1
  while i <= #text do
    if text:sub(i, i) == '<' then
      local close = text:find('>', i, true)
      if close then
        tokens[#tokens + 1] = text:sub(i, close)
        i = close + 1
      else
        tokens[#tokens + 1] = text:sub(i, i)
        i = i + 1
      end
    else
      local b = text:byte(i)
      local len = 1
      if b >= 0xf0 then
        len = 4
      elseif b >= 0xe0 then
        len = 3
      elseif b >= 0xc0 then
        len = 2
      end
      tokens[#tokens + 1] = text:sub(i, i + len - 1)
      i = i + len
    end
  end
  return tokens
end

--- A human-readable label for keymap dict `m` (as from `all`): its own
--- `desc` if set, else its string `rhs` (e.g. `<cmd>MepFindFiles<cr>`),
--- else a generic placeholder for a callback with neither.
function M.label(m)
  if m.desc and m.desc ~= '' then
    return m.desc
  end
  if m.rhs and m.rhs ~= '' then
    return m.rhs
  end
  return '<function>'
end

--- Every mapping in `all(mode, bufnr)` whose own key-token sequence
--- starts with `prefix_tokens` (as from `tokenize(keytrans(...))`, over
--- *its own* `lhsraw`): `{ m = <keymap dict>, tokens = <its own token
--- list> }` pairs, so callers don't have to re-tokenize.
---
--- Deliberately compares normalized *tokens*, not raw bytes: a
--- multi-key `lhsraw` as actually stored by a real `:map`-defined
--- mapping can byte-encode a control key like `<C-c>` differently
--- (`K_SPECIAL`-escaped, 3 bytes) than `nvim_replace_termcodes` does for
--- that same key in isolation (1 bare byte) — confirmed empirically
--- while building this — so byte-prefix matching between our own
--- computed prefix and a real mapping's `lhsraw` is unreliable.
--- `vim.fn.keytrans()` normalizes *both* representations to the same
--- human notation regardless of which byte form produced them, so
--- token-level comparison after that normalization is the only
--- consistently correct way to do this.
function M.matching(mode, bufnr, prefix_tokens)
  local out = {}
  for _, m in ipairs(M.all(mode, bufnr)) do
    local tokens = M.tokenize(vim.fn.keytrans(m.lhsraw))
    if #tokens >= #prefix_tokens then
      local is_prefix = true
      for i = 1, #prefix_tokens do
        if tokens[i] ~= prefix_tokens[i] then
          is_prefix = false
          break
        end
      end
      if is_prefix then
        out[#out + 1] = { m = m, tokens = tokens }
      end
    end
  end
  return out
end

--- The mappings under `prefix_raw`, grouped by their next key: `groups`
--- (a list of `{ key, desc, is_group, leaf, count }`, `key` in human
--- `<...>`/character notation, sorted by `key`) and `exact` (the one
--- mapping, if any, whose lhs is *exactly* `prefix_raw` — a leaf that
--- terminates right at this prefix, e.g. `prefix_raw` is itself a
--- complete binding as well as a prefix of longer ones). A `key` shared
--- by more than one mapping, or extended by a longer one, is a further
--- submenu (`is_group = true`, `count` mappings under it, no single
--- `desc` — a generic "+N mapping(s)" one instead, real which-key's own
--- "this is a group, not a command" convention); otherwise it's a `leaf`
--- (the one matching dict) you can execute directly.
---
--- **Known simplification**: when a key is *both* an exact leaf and a
--- prefix of longer mappings (a genuinely ambiguous binding — rare, and
--- none of this project's own keymaps do it), it's shown/treated as a
--- group only; the leaf itself becomes unreachable through the popup
--- (still reachable by typing the full sequence without ever triggering
--- mep.whichkey). Real Vim resolves this kind of ambiguity via
--- `timeoutlen`; replicating that exactly wasn't worth the complexity
--- here.
function M.compute_groups(mode, bufnr, prefix_raw)
  local prefix_tokens = M.tokenize(vim.fn.keytrans(prefix_raw))
  local n = #prefix_tokens
  local exact = nil
  local by_key = {}
  local order = {}

  for _, entry in ipairs(M.matching(mode, bufnr, prefix_tokens)) do
    local tokens = entry.tokens
    if #tokens == n then
      exact = entry.m
    else
      local key = tokens[n + 1]
      if not by_key[key] then
        by_key[key] = {}
        order[#order + 1] = key
      end
      table.insert(by_key[key], { m = entry.m, is_leaf = (#tokens == n + 1) })
    end
  end

  table.sort(order)
  local groups = {}
  for _, key in ipairs(order) do
    local entries = by_key[key]
    if #entries == 1 and entries[1].is_leaf then
      groups[#groups + 1] = { key = key, desc = M.label(entries[1].m), is_group = false, leaf = entries[1].m }
    else
      groups[#groups + 1] = { key = key, desc = '+' .. #entries .. ' mapping' .. (#entries > 1 and 's' or ''), is_group = true, count = #entries }
    end
  end

  return groups, exact
end

return M

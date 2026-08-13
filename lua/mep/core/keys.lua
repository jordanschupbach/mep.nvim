--- Global modifier-key placeholders for keymap lhs strings. Any keymap
--- option anywhere in mep can be written as `<Mod1-...>` instead of
--- hard-coding `<A-...>`/`<M-...>`; library configs expand the
--- placeholder (via `expand_table` in their own `setup()`) to the
--- concrete modifier resolved here.
---
--- `mod1` is the classic window-manager modifier: Alt (`'A'`) on
--- Linux/Windows, Option (`'M'`, i.e. Option-as-Meta) on macOS. Note
--- that Neovim itself treats `<A-...>` and `<M-...>` as the same
--- modifier — the macOS default is about intent, and about leaving the
--- door open to remapping: a macOS terminal must be configured to send
--- Option as Meta for either spelling to arrive at all (iTerm2's
--- "Option as Esc+", kitty's `macos_option_as_alt`, Neovide's
--- `macos_option_key_is_meta`), and a GUI user who prefers Cmd instead
--- can set `mods = { mod1 = 'D' }` once, globally, via
--- `require('mep').setup({ mods = { mod1 = 'D' } })` — see
--- mep.config.defaults.mods.
---
--- Names are `mod<N>` (case-insensitive in placeholders). Only `mod1`
--- has a built-in platform fallback; any other `modN` expands only if
--- the user configures it (e.g. `mods = { mod2 = 'C' }` makes
--- `<Mod2-x>` expand to `<C-x>`), and is otherwise left untouched.
local M = {}

-- Built-in per-platform fallbacks, used when `mep.config.options.mods`
-- doesn't name the modifier. Functions, not values: `vim.fn.has` is
-- checked at resolve time, keeping this module free of require-time
-- work.
local FALLBACKS = {
  mod1 = function()
    return vim.fn.has('mac') == 1 and 'M' or 'A'
  end,
}

--- Resolve a modifier name ('mod1', 'mod2', ...) to its concrete Neovim
--- modifier letter ('A', 'M', 'C', 'D', ...): the user's
--- `mods.<name>` from mep.config if set, else the built-in platform
--- fallback, else nil.
function M.resolve(name)
  name = name:lower()
  -- Required lazily: mep.config is the user-facing options store and
  -- must be readable at its post-setup() state, and a top-level require
  -- here would also be a (harmless but avoidable) load-order knot.
  local config = require('mep.config')
  local mods = config.options and config.options.mods
  local configured = mods and mods[name]
  if type(configured) == 'string' and configured ~= '' then
    return configured
  end
  local fallback = FALLBACKS[name]
  if fallback then
    return fallback()
  end
  return nil
end

--- Expand every `<ModN-...>` placeholder in a single lhs string
--- (`'<Mod1-S-h>'` -> `'<A-S-h>'` with mod1 = 'A'). Case-insensitive on
--- the placeholder name; unknown/unconfigured names are left as-is.
--- Non-strings pass through untouched.
function M.expand(lhs)
  if type(lhs) ~= 'string' then
    return lhs
  end
  return (lhs:gsub('<([Mm][Oo][Dd]%d+)%-', function(name)
    local resolved = M.resolve(name)
    if resolved then
      return '<' .. resolved .. '-'
    end
    -- nil tells gsub to keep the original text.
    return nil
  end))
end

--- Recursively expand placeholders in every string value of a table,
--- in place (nested tables included), and return it. Library configs
--- call this on the freshly merged copy of their options, so the
--- stored defaults are never mutated.
function M.expand_table(tbl)
  for key, value in pairs(tbl) do
    if type(value) == 'string' then
      tbl[key] = M.expand(value)
    elseif type(value) == 'table' then
      M.expand_table(value)
    end
  end
  return tbl
end

return M

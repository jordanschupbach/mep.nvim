--- Aggregator for mep's theme library: a curated collection of
--- popular colorscheme palettes (`mep.theme.palettes`) rendered by one
--- shared, data-driven highlight-group generator (`mep.theme.engine`),
--- plus a fuzzy picker (`mep.picker`-backed) with mep-wm-style live
--- preview — move the selection and the whole editor re-colors
--- immediately, Enter commits, Escape (or any other way of closing
--- without picking) reverts to whatever was active before you opened
--- it.
local config = require('mep.theme.config')
local palettes = require('mep.theme.palettes')
local engine = require('mep.theme.engine')
local swatch = require('mep.theme.swatch')

local M = {}
M.engine = engine
M.swatch = swatch

local current_name = nil

--- Register a new theme (or override a built-in one) under `name` —
--- see `mep.theme.palettes`'s own header comment for the field schema
--- (`dark`, `bg`, `fg`, and seven accent hues are required; the rest
--- fall back sensibly). Available to `M.apply`/`M.list`/`M.picker`
--- immediately.
function M.register(name, palette)
  palettes.palettes[name] = vim.tbl_extend('force', { name = name }, palette)
end

--- Every registered theme name (built-in and `M.register`ed), sorted.
function M.list()
  local names = {}
  for name in pairs(palettes.palettes) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- The name last passed to a successful `M.apply`, or nil if that's
--- never happened this session.
function M.current()
  return current_name
end

--- Apply theme `name` (one of `M.list()`) to the running editor —
--- `hi clear` + every highlight group `mep.theme.engine.build`
--- produces for it, plus `'background'`/`vim.g.colors_name`. Warns
--- (without erroring) for an unknown name, or a registered palette
--- that's missing a required field.
function M.apply(name)
  local palette = palettes.palettes[name]
  if not palette then
    vim.notify('mep.theme: unknown theme "' .. tostring(name) .. '"', vim.log.levels.WARN)
    return
  end
  local missing = engine.missing_fields(palette)
  if #missing > 0 then
    vim.notify(
      'mep.theme: theme "' .. name .. '" is missing required field(s): ' .. table.concat(missing, ', '),
      vim.log.levels.ERROR
    )
    return
  end
  engine.apply(vim.tbl_extend('force', { name = name }, palette))
  current_name = name
end

--- Open a fuzzy picker over every registered theme (`require('mep.
--- picker').start`, `mep.url.pick`'s own "build opts inline, call
--- `picker.start` directly" pattern — this isn't a `mep.picker.
--- sources.*` file, since it's specific to this library, not a
--- generic, reusable source). `preview` (fires on every selection
--- move, before Enter) does two things at once: applies the
--- highlighted theme live to the whole editor — the same "see it for
--- real before committing" idea `~/projects/mep-wm`'s own theme picker
--- uses — *and* renders a `mep.theme.swatch` color breakdown (one line
--- per palette field, a solid block of that color plus its hex) into
--- the picker's own preview sidebar, so you can compare bg/fg/accent
--- hues directly without having to go find something in your own
--- buffers colored by each one. `on_close` (fires on *every* close
--- path — Escape, `<C-c>`, the window closing, even as a precursor to a
--- real selection) reverts to whatever theme was current before the
--- picker opened; `on_select` (which always runs right after
--- `on_close` when an item was actually chosen) then re-applies the
--- committed one.
---
--- The current theme is put first in the item list (`mep.picker`
--- itself has no notion of an "initial selection" — it always starts
--- at item 1, and a plain `M.list()` sorts alphabetically) so opening
--- the picker starts selection right there — mep-wm's own "opening the
--- picker doesn't itself change anything until you navigate", not an
--- immediate live-preview jump to whatever's alphabetically first.
function M.picker()
  local before = current_name
  local items = M.list()
  if before then
    local rest = vim.tbl_filter(function(name)
      return name ~= before
    end, items)
    items = { before }
    vim.list_extend(items, rest)
  end
  require('mep.picker').start({
    prompt_title = 'Theme' .. (before and (' (current: ' .. before .. ')') or ''),
    items = items,
    entry_to_string = function(item)
      return (item == before) and (item .. '  (current)') or item
    end,
    preview = function(item, preview_buf, _preview_win)
      M.apply(item)
      swatch.render(preview_buf, item, engine.normalize(palettes.palettes[item]))
    end,
    on_close = function()
      if before then
        M.apply(before)
      end
    end,
    on_select = function(item)
      M.apply(item)
    end,
  })
end

--- Configure mep.theme (see mep.theme.config.defaults: `default`,
--- `apply_on_setup`, `keymaps.picker`) and, unless `apply_on_setup` is
--- false, apply `default` immediately.
function M.setup(opts)
  local options = config.setup(opts)
  if options.apply_on_setup then
    M.apply(options.default)
  end
  for _, lhs in ipairs(options.keymaps.picker) do
    vim.keymap.set('n', lhs, M.picker, { desc = 'mep.theme: open the theme picker' })
  end
  return options
end

--- Test/dev-only: forget which theme is "current" (`M.current()`),
--- without changing what's actually applied or touching the registered
--- palette table.
function M._reset()
  current_name = nil
end

return M

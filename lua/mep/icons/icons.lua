--- Aggregator for mep's icon library. Looks up file/directory glyphs by
--- name from the built-in tables in icons/data.lua, styled per
--- icons/config.lua (default: emoji, no special font required). Building
--- blocks: config.lua (defaults/overrides), data.lua (the icon tables).
local config = require('mep.icons.config')
local data = require('mep.icons.data')

local M = {}

local function resolved_table(style)
  local base = data[style] or data[config.defaults.style]
  local override = config.options.overrides and config.options.overrides[style]
  if not override then
    return base
  end
  return vim.tbl_deep_extend('force', base, override)
end

--- Configure the icons library. See mep.icons.config.defaults for the
--- `style` and `overrides` options. Icon lookups work with sensible
--- defaults even if this is never called.
function M.setup(opts)
  return config.setup(opts)
end

--- Icon (and a highlight group name) for a file, matched by exact
--- basename first (e.g. "Makefile", ".gitignore"), then by lowercased
--- extension, falling back to a generic file icon. `name` may be a bare
--- filename or a full path. `opts.style` overrides the configured style
--- for this one lookup.
function M.get_file_icon(name, opts)
  opts = opts or {}
  local t = resolved_table(opts.style or config.options.style)
  local basename = vim.fn.fnamemodify(name, ':t')
  local ext = vim.fn.fnamemodify(name, ':e'):lower()
  local icon = t.by_filename[basename] or (ext ~= '' and t.by_extension[ext]) or t.default_file
  return icon, 'MepIconFile'
end

--- Icon (and a highlight group name) for a directory, closed or expanded.
function M.get_directory_icon(is_open, opts)
  opts = opts or {}
  local t = resolved_table(opts.style or config.options.style)
  local icon = is_open and t.default_directory_open or t.default_directory
  return icon, 'MepIconDirectory'
end

--- The tree-expand marker (chevron-like glyph) for a closed/open
--- directory, styled consistently with the icon set (so 'ascii' style
--- stays fully 7-bit, not just its icons).
function M.get_expand_marker(is_open, opts)
  opts = opts or {}
  local t = resolved_table(opts.style or config.options.style)
  return is_open and t.expand_marker_open or t.expand_marker_closed
end

--- A small curated "UI action" icon, by semantic name (`'notifications'`
--- /`'todo'`/`'tests'`/`'git'`/`'add'`/`'clear'` — see icons/data.lua's
--- own header comment on `UI_ICONS` for what each traces back to),
--- styled the same way file/directory icons are. `nil` for an
--- unrecognized name (callers fall back to their own literal, the same
--- way `mep.activitybar.config.icon_for` does).
function M.get_ui_icon(name, opts)
  opts = opts or {}
  local t = resolved_table(opts.style or config.options.style)
  return t.ui_icons and t.ui_icons[name]
end

return M

--- Aggregator for mep's org-roam-style library: note search-and-insert
--- (`mep.roam.picker`), a backlinks panel (`mep.roam.backlinks`), daily/
--- journal notes (`mep.roam.daily`), and new-note creation (`mep.roam.
--- create`) — all over org headlines with `:ID:` properties
--- (`mep.org.id`) linked via plain `[[id:...]]` links (`mep.org.link`),
--- this project's own single ID/link mechanism, not a separate one.
local config = require('mep.roam.config')
local notes = require('mep.roam.notes')
local picker_mod = require('mep.roam.picker')
local backlinks = require('mep.roam.backlinks')
local daily = require('mep.roam.daily')
local create = require('mep.roam.create')

local M = {}
M.notes = notes
M.backlinks = backlinks
M.daily = daily
M.create = create

--- Open the note search-and-insert picker. `<CR>` inserts a
--- `[[id:...][title]]` link at the cursor.
function M.picker()
  require('mep.picker').start(picker_mod.picker_opts(config.options.roam_dirs))
end

--- Toggle the backlinks panel for the current buffer's note.
function M.toggle_backlinks()
  backlinks.toggle()
end

--- Open (creating if missing) today's daily note.
function M.today()
  daily.open_today(config.options.roam_dirs, config.options.daily_template)
end

--- Prompt for a title and create a new note.
function M.new_note()
  create.new_note_interactive(config.options.roam_dirs)
end

--- Configure mep.roam: `roam_dirs`, `daily_template`, `sidebar`
--- geometry, and `keymaps.insert`/`backlinks`/`today`/`new_note`
--- (global — see mep.roam.config.defaults). Works with sensible
--- defaults even if this is never called (though `roam_dirs` defaults
--- to `{}`, so there's nothing to search/link until you configure it).
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.insert) do
    vim.keymap.set('n', lhs, M.picker, { desc = 'mep.roam: insert a link to a note' })
  end
  for _, lhs in ipairs(options.keymaps.backlinks) do
    vim.keymap.set('n', lhs, M.toggle_backlinks, { desc = 'mep.roam: toggle backlinks panel' })
  end
  for _, lhs in ipairs(options.keymaps.today) do
    vim.keymap.set('n', lhs, M.today, { desc = 'mep.roam: open today\'s daily note' })
  end
  for _, lhs in ipairs(options.keymaps.new_note) do
    vim.keymap.set('n', lhs, M.new_note, { desc = 'mep.roam: create a new note' })
  end
  return options
end

return M

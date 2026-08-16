--- Aggregator for mep's spaced-repetition flashcard library (org-drill
--- style): review sessions over org headlines tagged `config.options.
--- tag` (`:drill:` by default), SM-2 scheduling state
--- (`mep.flashcards.sm2`) stored per-headline via `mep.org.property`
--- (`mep.flashcards.state`), collected across `config.options.
--- drill_files` (`mep.flashcards.collect`) and reviewed through a
--- popup UI (`mep.flashcards.review`).
local config = require('mep.flashcards.config')
local collect = require('mep.flashcards.collect')
local review = require('mep.flashcards.review')

local M = {}
M.sm2 = require('mep.flashcards.sm2')
M.state = require('mep.flashcards.state')
M.collect = collect
M.review = review

--- Start a review session over every card due in `config.options.
--- drill_files`. A no-op (with a notification) if none are due.
function M.review_session()
  review.start(collect.due_entries(config.options.drill_files, config.options.tag))
end

--- Configure mep.flashcards: `drill_files`, `tag`, and `keymaps.review`
--- (global — see mep.flashcards.config.defaults). Works with sensible
--- defaults even if this is never called (though `drill_files` defaults
--- to `{}`, so there's nothing to review until you configure it).
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.review) do
    vim.keymap.set('n', lhs, M.review_session, { desc = 'mep.flashcards: start a review session' })
  end
  return options
end

return M

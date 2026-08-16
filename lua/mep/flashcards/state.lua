--- Per-headline SM-2 state, stored in the headline's own `:PROPERTIES:`
--- drawer via `mep.org.property` — reusing that existing store rather
--- than building a separate one, as this library's own design brief
--- calls for. A narrower property set than real org-drill's own (which
--- also tracks failure counts, last-quality, last-reviewed date, ...) —
--- just what `mep.flashcards.sm2` needs to keep scheduling: `:DRILL_EF:`
--- (easiness factor), `:DRILL_REPS:` (repetition count), `:DRILL_
--- INTERVAL:` (days), `:DRILL_DUE:` (`"YYYY-MM-DD"`, next review date).
local property = require('mep.org.property')
local sm2 = require('mep.flashcards.sm2')

local M = {}

local KEYS = { ef = 'DRILL_EF', reps = 'DRILL_REPS', interval = 'DRILL_INTERVAL', due = 'DRILL_DUE' }

--- The headline at `lnum`'s own SM-2 state: `{ ef, reps, interval, due
--- }` — `due` is `nil` for a never-reviewed card (always due), a
--- `"YYYY-MM-DD"` string otherwise. Falls back to `sm2.DEFAULT` (`due =
--- nil`) for any property that's missing or fails to parse as a number,
--- so a hand-edited or partially-written drawer degrades to "treat it
--- as new" rather than erroring.
function M.read(bufnr, lnum)
  local ef = tonumber(property.get(bufnr, lnum, KEYS.ef))
  local reps = tonumber(property.get(bufnr, lnum, KEYS.reps))
  local interval = tonumber(property.get(bufnr, lnum, KEYS.interval))
  local due = property.get(bufnr, lnum, KEYS.due)
  return {
    ef = ef or sm2.DEFAULT.ef,
    reps = reps or sm2.DEFAULT.reps,
    interval = interval or sm2.DEFAULT.interval,
    due = due,
  }
end

--- Write `state` (`M.read`'s own shape) back to the headline at `lnum`'s
--- properties drawer. Buffer-only — like `mep.org.agenda`'s own TODO-
--- cycle keymap, this doesn't save the file; the user's own save
--- workflow (or an autocmd they set up) persists it, consistent with
--- this project not writing to disk behind the user's back anywhere
--- else either.
function M.write(bufnr, lnum, state)
  property.set(bufnr, lnum, KEYS.ef, string.format('%.2f', state.ef))
  property.set(bufnr, lnum, KEYS.reps, tostring(state.reps))
  property.set(bufnr, lnum, KEYS.interval, tostring(state.interval))
  property.set(bufnr, lnum, KEYS.due, state.due)
end

--- Whether a card with `state.due` (as read by `M.read`) is due for
--- review on or before `today` (`"YYYY-MM-DD"`, default `os.date('%Y-
--- %m-%d')`) — a never-reviewed card (`due == nil`) always is. Plain
--- string comparison is correct for ISO `YYYY-MM-DD` dates.
function M.is_due(state, today)
  today = today or os.date('%Y-%m-%d')
  return state.due == nil or state.due <= today
end

return M

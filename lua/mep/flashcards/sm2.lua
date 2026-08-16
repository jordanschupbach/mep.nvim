--- The SM-2 spaced-repetition algorithm (Wozniak, 1987 — the same
--- scheduling core Anki/real org-drill both build on), pure and
--- state-in-state-out: no buffer/property access at all, see
--- `mep.flashcards.state` for that half.
local M = {}

--- A never-reviewed card's starting state: easiness factor 2.5 (SM-2's
--- own standard starting point), zero repetitions, zero interval (due
--- immediately).
M.DEFAULT = { ef = 2.5, reps = 0, interval = 0 }

-- The four-button grade vocabulary this project's review UI uses
-- (`mep.flashcards.review`), each mapped to SM-2's own 0-5 "quality of
-- recall" scale — a deliberate simplification of the full 6-point scale
-- down to the 4 buttons Anki popularized and users actually expect.
M.QUALITY = { again = 0, hard = 3, good = 4, easy = 5 }

--- The next `{ ef, reps, interval }` after grading `state` (as `M.
--- DEFAULT`'s own shape) with `grade` (a key of `M.QUALITY`). `interval`
--- is in whole days, rounded. A `quality < 3` ("again") resets
--- repetitions and restarts at a 1-day interval, matching real SM-2's
--- own "forgot it, start over" rule; `hard`/`good`/`easy` all grow the
--- interval (1 day -> 6 days -> `interval * ef`, real SM-2's own
--- schedule), `ef` itself adjusted by the standard SM-2 formula
--- (`EF' = EF + (0.1 - (5-q)*(0.08+(5-q)*0.02))`, floored at 1.3).
function M.grade(state, grade)
  state = state or M.DEFAULT
  local quality = M.QUALITY[grade]
  assert(quality, 'mep.flashcards.sm2.grade: unknown grade "' .. tostring(grade) .. '"')

  local ef = state.ef + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
  if ef < 1.3 then
    ef = 1.3
  end

  local reps, interval
  if quality < 3 then
    reps = 0
    interval = 1
  else
    reps = state.reps + 1
    if state.reps == 0 then
      interval = 1
    elseif state.reps == 1 then
      interval = 6
    else
      interval = math.max(1, math.floor(state.interval * ef + 0.5))
    end
  end

  return { ef = ef, reps = reps, interval = interval }
end

--- `state.interval` days after `today` (a `"YYYY-MM-DD"` string,
--- default `os.date('%Y-%m-%d')`), as the same `"YYYY-MM-DD"` shape —
--- what gets written to a headline's own `:DRILL_DUE:` property.
function M.due_date(state, today)
  today = today or os.date('%Y-%m-%d')
  local y, m, d = today:match('(%d+)-(%d+)-(%d+)')
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  return os.date('%Y-%m-%d', t + state.interval * 86400)
end

return M

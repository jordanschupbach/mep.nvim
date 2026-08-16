--- Tracks the live REPL sessions this library has started — keyed by
--- `mep.repl.repl`'s own scope key (a filetype string, or a bufnr,
--- depending on `config.options.scope`), each a plain `{ bufnr, win,
--- job_id, source_win }` table. Pure bookkeeping, no window/job logic
--- of its own.
local M = {}

local sessions = {}

function M.get(key)
  return sessions[key]
end

function M.set(key, session)
  sessions[key] = session
end

function M.clear(key)
  sessions[key] = nil
end

--- Every tracked session, keyed the same way `get`/`set` are — used by
--- `mep.repl.repl.jump_back` to find which session (if any) the
--- *current* buffer belongs to.
function M.all()
  return sessions
end

--- Test/dev-only: forget every tracked session (does not itself kill
--- any real job — callers that actually want that do so before calling
--- this).
function M._reset()
  sessions = {}
end

return M

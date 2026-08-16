--- The busted (Lua) runner — this project's own test suite, and the
--- unconditional last-resort default `mep.activitybar.test_runners.
--- resolve` falls back to when nothing else matches (per the TODO this
--- generalization grew from: "Set up for this project, i.e. busted
--- lua... allow for configurable extensions").
---
--- **Scope note**: `parse_output` is written against busted's own
--- default terminal reporter output (`"N successes / M failures / ..."`
--- summary line, then a blank-line-or-next-header-delimited `"Failure ->
--- file @ line"`/`"Error -> file @ line"` block per failure). A fully
--- generic "parse any test framework's terminal output" parser isn't
--- attempted anywhere in `test_runners/` — each runner here is written
--- against its own framework's default plain-text reporter; point
--- `cmd` at a JSON/machine-readable reporter and write your own runner
--- module (same `{ name, detect, cmd, cwd_for, parse_output }` shape)
--- if a framework's plain text doesn't look like what's assumed here.
local M = {}

M.name = 'busted'
M.cmd = { 'busted' }

function M.cwd_for(cwd)
  return cwd
end

--- Never actually consulted by `resolve()` (busted is the unconditional
--- fallback, not detected-into), but kept for shape-consistency with
--- every other runner module.
function M.detect(_cwd)
  return true
end

--- Parse busted-style terminal output `text` into `{ summary (string or
--- nil), successes, failures, errors, pending (numbers, all 0 if no
--- summary line was found), failure_blocks (a list of `{ header, body
--- (list of lines) }`, in output order) }`. A line-based scan, not a
--- single regex: a failure's body runs until the *next*
--- `Failure ->`/`Error ->` header or end of input, which tolerates
--- whichever blank-line spacing convention is around it (busted's own
--- default reporter and running under a different terminal width don't
--- always agree on that).
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  local i = 1
  while i <= #lines do
    -- Lua patterns can't quantify a multi-char group ("(es)?" isn't
    -- optional-group syntax here, parens are only for captures), so
    -- "success"/"successes" needs `%a*` (any following letters) rather
    -- than the `s?`-suffix trick that works fine for "failure(s)"/
    -- "error(s)" (those only ever add a single trailing "s").
    local s, f, e, p = lines[i]:match('(%d+) success%a* / (%d+) failures? / (%d+) errors? / (%d+) pending')
    if s then
      result.summary = lines[i]
      result.successes, result.failures, result.errors, result.pending = tonumber(s), tonumber(f), tonumber(e), tonumber(p)
    end

    local header = lines[i]:match('^Failure %-> (.+)$') or lines[i]:match('^Error %-> (.+)$')
    if header then
      local body = {}
      local j = i + 1
      while lines[j] and not lines[j]:match('^Failure %-> ') and not lines[j]:match('^Error %-> ') do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      while #body > 0 and body[#body]:match('^%s*$') do
        table.remove(body)
      end
      result.failure_blocks[#result.failure_blocks + 1] = { header = header, body = body }
      i = j
    else
      i = i + 1
    end
  end

  return result
end

return M

--- Registry + auto-detection for `mep.activitybar.tests`' pluggable
--- test runners: one module per framework (`go`/`cargo`/`jest`/
--- `pytest`/`busted`), each `{ name, cmd, cwd_for(cwd), detect(cwd),
--- parse_output(text) }` — see any sibling module's own header comment
--- for its own output-format assumptions.
---
--- `M.resolve(cwd)` checks each detectable runner's own project-marker
--- file(s) in `ORDER`, first match wins; `busted` is never in `ORDER`
--- — it's the unconditional last-resort default (`M.resolve` falls
--- back to it), matching this project's own primary language rather
--- than being detected into via a marker file the way the others are.
local M = {}

M.registry = {
  go = require('mep.activitybar.test_runners.go'),
  cargo = require('mep.activitybar.test_runners.cargo'),
  jest = require('mep.activitybar.test_runners.jest'),
  pytest = require('mep.activitybar.test_runners.pytest'),
  busted = require('mep.activitybar.test_runners.busted'),
}

local ORDER = { 'go', 'cargo', 'jest', 'pytest' }

--- The first `ORDER`-listed runner whose `detect(cwd)` finds its own
--- project marker, or `registry.busted` if none do.
function M.resolve(cwd)
  for _, name in ipairs(ORDER) do
    local runner = M.registry[name]
    if runner.detect(cwd) then
      return runner
    end
  end
  return M.registry.busted
end

return M

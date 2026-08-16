--- The `go test` runner — detected by a `go.mod` in the project's `cwd`.
--- `-v` is required in `cmd` (unlike a bare `go test ./...`) so every
--- individual test prints its own `--- PASS:`/`--- FAIL:` line; without
--- it, a passing package only prints one `ok  <pkg>  <time>` line and
--- per-test pass counts are unrecoverable from the output at all.
local M = {}

M.name = 'go'
M.cmd = { 'go', 'test', '-v', './...' }

function M.cwd_for(cwd)
  return cwd
end

function M.detect(cwd)
  return vim.fn.filereadable((cwd or vim.fn.getcwd()) .. '/go.mod') == 1
end

--- `text` is `go test -v`'s own terminal output: one `--- PASS: Test
--- Name (0.00s)`/`--- FAIL: TestName (0.00s)` line per test, a `FAIL`
--- body (indented, `t.Error`/`t.Fatal` output plus a trailing
--- `panic:`/stack trace on a real crash) between a `--- FAIL:` line and
--- whatever follows it, and a final `ok  <pkg>  <time>` or `FAIL
--- <pkg>  <time>` per package. No pending/skipped-count concept
--- (`errors`/`pending` are always 0 — a Go test that calls `t.Skip`
--- shows up as a `--- SKIP:` line, folded into `pending` here since
--- `go test` itself doesn't distinguish "skipped" from "would-be error"
--- the way busted's runner does).
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  local i = 1
  while i <= #lines do
    if lines[i]:match('^%-%-%- PASS: ') then
      result.successes = result.successes + 1
      i = i + 1
    elseif lines[i]:match('^%-%-%- SKIP: ') then
      result.pending = result.pending + 1
      i = i + 1
    else
      local header = lines[i]:match('^%-%-%- FAIL: (.+)$')
      if header then
        result.failures = result.failures + 1
        local body = {}
        local j = i + 1
        while lines[j] and not lines[j]:match('^%-%-%- ') and not lines[j]:match('^ok  ') and not lines[j]:match('^FAIL') do
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
  end

  local total = result.successes + result.failures + result.pending
  if total > 0 then
    result.summary = string.format(
      '%d successes / %d failures / %d pending',
      result.successes,
      result.failures,
      result.pending
    )
  end

  return result
end

return M

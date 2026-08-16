--- The `cargo test` runner — detected by a `Cargo.toml` in the
--- project's `cwd`.
local M = {}

M.name = 'cargo'
M.cmd = { 'cargo', 'test' }

function M.cwd_for(cwd)
  return cwd
end

function M.detect(cwd)
  return vim.fn.filereadable((cwd or vim.fn.getcwd()) .. '/Cargo.toml') == 1
end

--- `text` is `cargo test`'s own terminal output: one `test some::path
--- ... ok`/`... FAILED` line per test while the suite runs, a
--- `failures:` section afterward with one `---- some::path stdout
--- ----` block per failed test (its captured output/panic message),
--- and a final `test result: FAILED. N passed; M failed; K ignored; 0
--- measured; 0 filtered out` (or `test result: ok. ...` when nothing
--- failed) summary line. `errors` stays 0 — cargo test has no separate
--- "error" outcome distinct from a failed assertion/panic; `ignored`
--- maps to `pending`.
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  for _, line in ipairs(lines) do
    local passed, failed, ignored = line:match('test result: %a+%. (%d+) passed; (%d+) failed; (%d+) ignored')
    if passed then
      result.summary = line
      result.successes, result.failures, result.pending = tonumber(passed), tonumber(failed), tonumber(ignored)
    end
  end

  local i = 1
  while i <= #lines do
    local header = lines[i]:match('^%-%-%-%- (.+) stdout %-%-%-%-$')
    if header then
      local body = {}
      local j = i + 1
      while lines[j] and not lines[j]:match('^%-%-%-%- .+ stdout %-%-%-%-$') and not lines[j]:match('^failures:$') do
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

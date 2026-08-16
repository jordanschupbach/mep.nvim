--- The `jest` runner — detected by a `package.json` in the project's
--- `cwd` that references jest (a `"jest"` dependency/devDependency/
--- config key, or a standalone `jest.config.*` file alongside it).
local M = {}

M.name = 'jest'
M.cmd = { 'npx', 'jest', '--verbose' }

function M.cwd_for(cwd)
  return cwd
end

function M.detect(cwd)
  cwd = cwd or vim.fn.getcwd()
  if vim.fn.glob(cwd .. '/jest.config.*') ~= '' then
    return true
  end
  local pkg_path = cwd .. '/package.json'
  if vim.fn.filereadable(pkg_path) ~= 1 then
    return false
  end
  local ok, decoded = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(pkg_path), '\n'))
  if not ok or type(decoded) ~= 'table' then
    return false
  end
  return decoded.jest ~= nil
    or (decoded.dependencies ~= nil and decoded.dependencies.jest ~= nil)
    or (decoded.devDependencies ~= nil and decoded.devDependencies.jest ~= nil)
end

--- `text` is `jest --verbose`'s own terminal output: one ` PASS`/`
--- FAIL` (or, per-test with `--verbose`, an indented `✓`/`✗ some test
--- name`) line while the suite runs, a failure detail block starting
--- with `  ● describe block › test name` for each failed test (its
--- assertion diff/stack trace follows, indented, until the next `  ●`
--- or the closing `Tests:` summary), and a final `Tests: N failed, M
--- passed, K skipped, T total` summary line (any of the count fields
--- may be absent if that count is 0 — jest omits zero-count fields
--- rather than printing "0 failed"). `errors` stays 0 — jest has no
--- separate "error" outcome distinct from a failed assertion/thrown
--- exception; `skipped`/`todo` map to `pending`.
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  for _, line in ipairs(lines) do
    if line:match('^Tests:%s') then
      result.summary = line
      local failed = line:match('(%d+) failed')
      local passed = line:match('(%d+) passed')
      local skipped = line:match('(%d+) skipped')
      local todo = line:match('(%d+) todo')
      result.failures = tonumber(failed) or 0
      result.successes = tonumber(passed) or 0
      result.pending = (tonumber(skipped) or 0) + (tonumber(todo) or 0)
    end
  end

  local i = 1
  while i <= #lines do
    local header = lines[i]:match('^%s*● (.+)$')
    if header then
      local body = {}
      local j = i + 1
      while lines[j] and not lines[j]:match('^%s*● ') and not lines[j]:match('^Tests:%s') do
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

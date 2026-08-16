--- The `pytest` runner — detected by `pytest.ini`, a `pyproject.toml`
--- with a `[tool.pytest.ini_options]` table, or a `setup.cfg` with a
--- `[tool:pytest]` section, in the project's `cwd`.
local M = {}

M.name = 'pytest'
M.cmd = { 'pytest', '-v' }

function M.cwd_for(cwd)
  return cwd
end

local function file_contains(path, needle)
  if vim.fn.filereadable(path) ~= 1 then
    return false
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    if line:find(needle, 1, true) then
      return true
    end
  end
  return false
end

function M.detect(cwd)
  cwd = cwd or vim.fn.getcwd()
  if vim.fn.filereadable(cwd .. '/pytest.ini') == 1 then
    return true
  end
  if file_contains(cwd .. '/pyproject.toml', '[tool.pytest.ini_options]') then
    return true
  end
  if file_contains(cwd .. '/setup.cfg', '[tool:pytest]') then
    return true
  end
  return false
end

--- `text` is `pytest -v`'s own terminal output: one `path/to/
--- test_file.py::test_name PASSED`/`FAILED`/`SKIPPED` line per test
--- while the suite runs, a `FAILURES` section afterward with one
--- `________________ test_name ________________` separator (a row of
--- underscores around the test name) per failed test followed by its
--- traceback until the next separator or the closing summary line, and
--- a final `===== N failed, M passed, K skipped in T.TTs =====` (any
--- count field may be absent if 0). `errors` maps from pytest's own
--- separate "error" outcome (a fixture/collection error, distinct from
--- a failed assertion) when present in the summary line.
function M.parse_output(text)
  local lines = vim.split(text, '\n', { plain = true })
  local result = { summary = nil, successes = 0, failures = 0, errors = 0, pending = 0, failure_blocks = {} }

  for _, line in ipairs(lines) do
    if line:match('^=+ .* =+$') and (line:match('passed') or line:match('failed') or line:match('error')) then
      result.summary = line
      result.failures = tonumber(line:match('(%d+) failed')) or 0
      result.successes = tonumber(line:match('(%d+) passed')) or 0
      result.pending = tonumber(line:match('(%d+) skipped')) or 0
      result.errors = tonumber(line:match('(%d+) error')) or 0
    end
  end

  local i = 1
  while i <= #lines do
    local header = lines[i]:match('^_+ (.+) _+$')
    if header then
      local body = {}
      local j = i + 1
      while lines[j] and not lines[j]:match('^_+ .+ _+$') and not lines[j]:match('^=+ .* =+$') do
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

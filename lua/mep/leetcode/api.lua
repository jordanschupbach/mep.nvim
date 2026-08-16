--- LeetCode's own (unofficial, reverse-engineered — the query/endpoint
--- shapes community tools like leetcode-cli/vscode-leetcode use, not
--- independently verified against a live account from this environment)
--- GraphQL + REST API, over real `curl` subprocesses (`mep.core.job`,
--- the same "temp file body, --fail-with-body, JSON over stdout" idiom
--- `mep.ai.job`'s own `M.request` uses — see that module's header
--- comment) — network calls only ever happen from `M.fetch_problem`/
--- `M.submit`, both explicit user actions, matching `mep.ai`'s own
--- "only shells out if you actually use it" posture.
---
--- Credentials are two browser cookie values from a logged-in LeetCode
--- session (`LEETCODE_SESSION` + `csrftoken`, copied out of your
--- browser's devtools) — read from environment variables
--- (`config.options.session_cookie_env`/`csrf_token_env`), never
--- hardcoded or persisted by this module itself.
local core = require('mep.core')
local config = require('mep.leetcode.config')

local M = {}

local BASE = 'https://leetcode.com'

M.poll_interval_ms = 1500
M.poll_max_attempts = 20

--- `{ session, csrf }` read from the two configured env vars, or nil
--- plus an explanatory message if either is unset/empty.
function M.credentials()
  local session = vim.env[config.options.session_cookie_env]
  local csrf = vim.env[config.options.csrf_token_env]
  if not session or session == '' or not csrf or csrf == '' then
    return nil,
      string.format(
        'mep.leetcode: missing credentials — set $%s/$%s (copy the LEETCODE_SESSION/csrftoken cookie values from a logged-in browser session)',
        config.options.session_cookie_env,
        config.options.csrf_token_env
      )
  end
  return { session = session, csrf = csrf }
end

local function cookie_headers(creds)
  return {
    '-H',
    'Cookie: LEETCODE_SESSION=' .. creds.session .. '; csrftoken=' .. creds.csrf,
    '-H',
    'x-csrftoken: ' .. creds.csrf,
  }
end

local function post_json(url, creds, extra_headers, json_body, on_done)
  local body_path = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode(json_body) }, body_path)

  local cmd = { 'curl', '-s', '--fail-with-body', '-X', 'POST', url, '-H', 'Content-Type: application/json' }
  vim.list_extend(cmd, cookie_headers(creds))
  vim.list_extend(cmd, extra_headers or {})
  vim.list_extend(cmd, { '--data-binary', '@' .. body_path })

  local raw, stderr_lines = {}, {}
  core.job.spawn({
    cmd = cmd,
    on_stdout = function(l)
      raw[#raw + 1] = l
    end,
    on_stderr = function(l)
      stderr_lines[#stderr_lines + 1] = l
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, body_path)
      if code ~= 0 then
        on_done('request failed (exit ' .. code .. '): ' .. (stderr_lines[1] or table.concat(raw, '\n')), nil)
        return
      end
      local ok, decoded = pcall(vim.json.decode, table.concat(raw, '\n'))
      if not ok or type(decoded) ~= 'table' then
        on_done('could not parse response: ' .. table.concat(raw, '\n'), nil)
        return
      end
      on_done(nil, decoded)
    end,
  })
end

local function get_json(url, creds, on_done)
  local cmd = { 'curl', '-s', '--fail-with-body', url }
  vim.list_extend(cmd, cookie_headers(creds))

  local raw, stderr_lines = {}, {}
  core.job.spawn({
    cmd = cmd,
    on_stdout = function(l)
      raw[#raw + 1] = l
    end,
    on_stderr = function(l)
      stderr_lines[#stderr_lines + 1] = l
    end,
    on_exit = function(code)
      if code ~= 0 then
        on_done('request failed (exit ' .. code .. '): ' .. (stderr_lines[1] or table.concat(raw, '\n')), nil)
        return
      end
      local ok, decoded = pcall(vim.json.decode, table.concat(raw, '\n'))
      if not ok or type(decoded) ~= 'table' then
        on_done('could not parse response: ' .. table.concat(raw, '\n'), nil)
        return
      end
      on_done(nil, decoded)
    end,
  })
end

local QUESTION_QUERY = [[
query questionData($titleSlug: String!) {
  question(titleSlug: $titleSlug) {
    questionId
    title
    titleSlug
    content
    difficulty
    codeSnippets { lang langSlug code }
    sampleTestCase
  }
}
]]

--- Fetch a problem's statement/starter code by its URL slug (e.g.
--- `'two-sum'`). `on_done(err, question)` — `question` is the raw
--- `data.question` object (`title`/`content` (HTML)/`difficulty`/
--- `codeSnippets`/`sampleTestCase`/`questionId`) on success, `err` a
--- string (missing credentials, network failure, unparseable/empty
--- response) otherwise.
function M.fetch_problem(slug, on_done)
  local creds, err = M.credentials()
  if not creds then
    on_done(err, nil)
    return
  end
  post_json(
    BASE .. '/graphql',
    creds,
    nil,
    { query = QUESTION_QUERY, variables = { titleSlug = slug }, operationName = 'questionData' },
    function(post_err, decoded)
      if post_err then
        on_done('mep.leetcode: ' .. post_err, nil)
        return
      end
      local question = decoded.data and decoded.data.question
      if not question then
        on_done('mep.leetcode: no such problem "' .. slug .. '"', nil)
        return
      end
      on_done(nil, question)
    end
  )
end

--- Submit `code` (in language `lang_slug`, e.g. `'python3'`/`'golang'`
--- — LeetCode's own per-language slugs, not always identical to `mep.
--- org.babel.languages`' own keys) for problem `slug`/`question_id`,
--- then poll its check endpoint (`M.poll_interval_ms` apart, up to `M.
--- poll_max_attempts` times) until a verdict lands. `on_done(err,
--- result)` — `result` is the raw check-endpoint response
--- (`status_msg`/`total_correct`/`total_testcases`/`status_runtime`/
--- `status_memory`) on success; `err` a string (missing credentials,
--- network failure, or "timed out waiting for a verdict" if it never
--- finished polling) otherwise.
function M.submit(slug, question_id, lang_slug, code, on_done)
  local creds, err = M.credentials()
  if not creds then
    on_done(err, nil)
    return
  end

  post_json(
    BASE .. '/problems/' .. slug .. '/submit/',
    creds,
    { '-H', 'Referer: ' .. BASE .. '/problems/' .. slug .. '/' },
    { lang = lang_slug, question_id = question_id, typed_code = code },
    function(post_err, decoded)
      if post_err then
        on_done('mep.leetcode: ' .. post_err, nil)
        return
      end
      local submission_id = decoded.submission_id
      if not submission_id then
        on_done('mep.leetcode: submit did not return a submission id', nil)
        return
      end

      local check_url = BASE .. '/submissions/detail/' .. tostring(submission_id) .. '/check/'
      local attempt = 0
      local function poll()
        attempt = attempt + 1
        get_json(check_url, creds, function(get_err, result)
          if get_err then
            on_done('mep.leetcode: ' .. get_err, nil)
          elseif result.state == 'SUCCESS' then
            on_done(nil, result)
          elseif attempt >= M.poll_max_attempts then
            on_done('mep.leetcode: timed out waiting for a verdict', nil)
          else
            vim.defer_fn(poll, M.poll_interval_ms)
          end
        end)
      end
      poll()
    end
  )
end

return M

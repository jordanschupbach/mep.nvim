--- Runs chat requests as real `curl` subprocesses (via mep.core.job,
--- the same job-runner mep.org.babel/mep.picker already use) — no HTTP
--- client Lua dependency needed, matching this project's zero-runtime-
--- dependency convention (`curl` is an external tool, the same class of
--- dependency as `git`/a C compiler already are for mep.treesitter).
---
--- The request body is written to a temp file and passed via `curl
--- --data-binary @<path>` rather than piped over the child's stdin —
--- the same "temp file, not process stdin" idiom mep.org.babel's own
--- compiled-language execution already uses, so there's only one way
--- this project talks to a subprocess that needs bulk input, not two.
--- `--fail-with-body` makes curl's own exit code reflect the HTTP
--- status (nonzero on 4xx/5xx) while still printing the error body, so
--- an auth failure or bad model name surfaces as a real error message
--- instead of a silent empty stream.
---
--- Two entry points: `M.start` streams (SSE), for `mep.ai.ai`'s own
--- simple flows; `M.request` doesn't (one JSON body, read in full),
--- for `mep.ai.agent`'s tool-calling turns — see `mep.ai.providers`'s
--- own header comment for why tool-calling specifically doesn't stream.
--- They share `build_curl_cmd`/`failure_detail` below; each still owns
--- its own `on_exit` handling since what counts as success/failure
--- differs (a stream needs at least one delta to have arrived, a
--- non-streaming request just needs a parseable body).
local core = require('mep.core')
local providers = require('mep.ai.providers')

local M = {}

--- `{ cmd, body_path }`: the `curl` invocation for `provider`/`body`
--- (already built by `mep.ai.providers.build_request`), and the temp
--- file its `--data-binary @<path>` points at — callers own deleting it
--- (in their own `on_exit`, after `curl` has read it) via
--- `pcall(vim.fn.delete, body_path)`.
local function build_curl_cmd(provider, body)
  local body_json = vim.json.encode(body)
  local body_path = vim.fn.tempname()
  vim.fn.writefile({ body_json }, body_path)

  local cmd = { 'curl', '-s', '--fail-with-body', '-X', 'POST', provider.endpoint, '-H', 'Content-Type: application/json' }
  for _, header in ipairs(providers.headers(provider)) do
    vim.list_extend(cmd, { '-H', header })
  end
  vim.list_extend(cmd, { '--data-binary', '@' .. body_path })
  return cmd, body_path
end

--- The best available failure detail from `stderr_lines`/`raw_lines`
--- (both plain line lists, accumulated by the caller's own `on_stderr`/
--- `on_stdout`): curl's own stderr (a network-level failure, e.g.
--- connection refused) if there is any, otherwise whatever the server's
--- own response body said — trying it as JSON first (`{"error":
--- {"message": "..."}}`/`{"message": "..."}`, the common shape across
--- every provider here), falling back to the raw text verbatim if it
--- doesn't parse as JSON at all (an HTML error page from a
--- misconfigured endpoint, say).
local function failure_detail(stderr_lines, raw_lines)
  if stderr_lines[1] then
    return stderr_lines[1]
  end
  if #raw_lines == 0 then
    return nil
  end
  local raw = table.concat(raw_lines, '\n')
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == 'table' then
    local err = decoded.error
    if type(err) == 'table' then
      return err.message or vim.json.encode(err)
    elseif type(err) == 'string' then
      return err
    end
    if decoded.message then
      return decoded.message
    end
  end
  return raw
end

--- Start streaming a chat request against `provider` (a resolved
--- provider table — see `mep.ai.ai`'s own `resolve_provider`, which
--- fills in `api_key`) with `messages` (`{ { role, content }, ... }`).
--- `on_delta(text)` fires for every non-empty text chunk as it streams
--- in; `on_done(err)` fires exactly once when the request finishes,
--- `err` nil on success or a string describing the failure. Returns a
--- handle with `kill()` (see mep.core.job.spawn) to cancel mid-stream.
function M.start(provider, messages, on_delta, on_done)
  local cmd, body_path = build_curl_cmd(provider, providers.build_request(provider, messages))
  -- Disable curl's own output buffering (streaming only — `M.request`
  -- below has no equivalent need, it reads the whole body at once
  -- either way), so SSE lines arrive as the server sends them, not
  -- batched at process exit.
  table.insert(cmd, 3, '-N')

  local raw_lines = {}
  local stderr_lines = {}
  local saw_delta = false
  -- Set by the wrapped handle's own `kill()` below — an intentional
  -- cancel makes `curl` exit nonzero (SIGTERM'd) with whatever partial
  -- SSE stream it had buffered on its way out, which would otherwise hit
  -- the `code ~= 0` failure path and surface as a scary-looking "request
  -- failed" error dumping that raw partial response — not a real
  -- failure at all, just the user asking to stop.
  local killed = false

  local handle = core.job.spawn({
    cmd = cmd,
    on_stdout = function(line)
      raw_lines[#raw_lines + 1] = line
      local data = line:match('^data:%s*(.*)$')
      if not data or data == '' or data == '[DONE]' then
        return
      end
      local ok, payload = pcall(vim.json.decode, data)
      if not ok or type(payload) ~= 'table' then
        return
      end
      local delta = providers.extract_delta(provider, payload)
      if delta and delta ~= '' then
        saw_delta = true
        on_delta(delta)
      end
    end,
    on_stderr = function(line)
      stderr_lines[#stderr_lines + 1] = line
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, body_path)
      if killed then
        on_done(nil)
      elseif code ~= 0 then
        local detail = failure_detail(stderr_lines, raw_lines)
        on_done(detail and ('request failed (exit ' .. code .. '): ' .. detail) or ('request failed (exit ' .. code .. ')'))
      elseif not saw_delta then
        -- Exit 0 (so not an HTTP/network failure `--fail-with-body`
        -- would have caught) but nothing ever came through — a genuinely
        -- empty completion is possible but unusual for this use case,
        -- so this is treated as worth surfacing rather than silently
        -- "succeeding" with no visible effect on the buffer.
        local detail = failure_detail(stderr_lines, raw_lines)
        on_done(detail and ('no response received: ' .. detail) or 'no response received')
      else
        on_done(nil)
      end
    end,
  })

  return {
    id = handle.id,
    kill = function()
      killed = true
      handle.kill()
    end,
  }
end

--- Send one non-streaming chat request against `provider` with
--- `messages`, optionally offering `tools` (a `mep.ai.tools`-shaped
--- list — see `mep.ai.providers.build_request`'s own `opts.tools`).
--- `on_done(err, parsed)` fires exactly once: `err` a string and
--- `parsed` nil on failure, or `err` nil and `parsed` the `mep.ai.
--- providers.parse_response`-shaped `{ text, tool_calls }` on success.
--- Returns a handle with `kill()`, same as `M.start`.
function M.request(provider, messages, tools, on_done)
  local body = providers.build_request(provider, messages, { stream = false, tools = tools })
  local cmd, body_path = build_curl_cmd(provider, body)

  local raw_lines = {}
  local stderr_lines = {}
  local killed = false

  local handle = core.job.spawn({
    cmd = cmd,
    on_stdout = function(line)
      raw_lines[#raw_lines + 1] = line
    end,
    on_stderr = function(line)
      stderr_lines[#stderr_lines + 1] = line
    end,
    on_exit = function(code)
      pcall(vim.fn.delete, body_path)
      if killed then
        on_done(nil, nil)
        return
      end
      if code ~= 0 then
        local detail = failure_detail(stderr_lines, raw_lines)
        on_done(detail and ('request failed (exit ' .. code .. '): ' .. detail) or ('request failed (exit ' .. code .. ')'), nil)
        return
      end
      local ok, decoded = pcall(vim.json.decode, table.concat(raw_lines, '\n'))
      if not ok or type(decoded) ~= 'table' then
        on_done('could not parse response: ' .. table.concat(raw_lines, '\n'), nil)
        return
      end
      on_done(nil, providers.parse_response(provider, decoded))
    end,
  })

  return {
    id = handle.id,
    kill = function()
      killed = true
      handle.kill()
    end,
  }
end

return M

--- Request-body shaping and response parsing for each `provider.kind`
--- `mep.ai.config`'s presets use. Pure functions only — no job/network
--- code here at all (that's `mep.ai.job`), so these are trivially
--- unit-testable against real, verbatim provider payloads.
---
--- Two kinds cover every preset `mep.ai.config` ships: `openai` (the
--- Chat Completions API shape — OpenAI itself, and any of the many
--- services, including a local Ollama's own `/v1/chat/completions`,
--- that deliberately mirror it) and `anthropic` (the Messages API).
---
--- `mep.ai.ai`'s own simple `send`/`send_selection` flows stream (SSE
--- `data: {...}` lines, blank line between events — `mep.ai.job` does
--- the actual line-by-line reading and hands each decoded JSON payload
--- to `M.extract_delta` here). `mep.ai.agent`'s tool-calling flow
--- instead sends `stream = false` (via `opts.stream` below) and reads
--- one complete JSON response body per turn through `M.parse_response`
--- — a tool call's own arguments can arrive split across many small SSE
--- deltas in either shape, and a turn that calls tools has to finish
--- entirely before anything (a decision about which tools to run) can
--- happen anyway, so streaming buys nothing there and only adds
--- accumulation complexity for both shapes at once.
local M = {}

--- `{ properties = {...}, required = {...} }` (JSON-Schema shape both
--- providers' own tool-parameter format is built on) from `mep.ai.
--- tools`'s own neutral `{ { name, type, description, required }, ... }`
--- list.
local function json_schema(parameters)
  local properties, required = {}, {}
  for _, param in ipairs(parameters or {}) do
    properties[param.name] = { type = param.type, description = param.description }
    if param.required then
      required[#required + 1] = param.name
    end
  end
  return properties, required
end

local function openai_tools(tools)
  if not tools then
    return nil
  end
  local out = {}
  for _, tool in ipairs(tools) do
    local properties, required = json_schema(tool.parameters)
    out[#out + 1] = {
      type = 'function',
      ['function'] = {
        name = tool.name,
        description = tool.description,
        parameters = { type = 'object', properties = properties, required = required },
      },
    }
  end
  return out
end

local function openai_request(provider, messages, opts)
  opts = opts or {}
  return {
    model = provider.model,
    messages = messages,
    stream = opts.stream ~= false,
    temperature = provider.temperature,
    tools = openai_tools(opts.tools),
  }
end

--- `data: {"choices":[{"delta":{"content":"..."}}]}` — the terminal
--- `data: [DONE]` line never reaches here (see `mep.ai.job`, which
--- filters it out before JSON-decoding at all, since it isn't JSON).
local function openai_delta(payload)
  local choice = payload.choices and payload.choices[1]
  return choice and choice.delta and choice.delta.content
end

--- A complete (non-streaming) OpenAI-shaped response body:
--- `{choices:[{message:{content, tool_calls:[{id, function:{name,
--- arguments: "<json string>"}}]}}]}` — `arguments` is itself a JSON
--- string (not a nested object the way Anthropic's `input` already is),
--- decoded here so every provider's `M.parse_response` returns the same
--- `{ text, tool_calls = { { id, name, arguments = <table> }, ... } }`
--- shape regardless.
local function openai_parse_response(body)
  local message = body.choices and body.choices[1] and body.choices[1].message or {}
  local tool_calls = {}
  for _, call in ipairs(message.tool_calls or {}) do
    local ok, arguments = pcall(vim.json.decode, call['function'].arguments)
    tool_calls[#tool_calls + 1] = {
      id = call.id,
      name = call['function'].name,
      arguments = ok and arguments or {},
      raw_arguments = call['function'].arguments,
    }
  end
  return { text = message.content or '', tool_calls = tool_calls }
end

--- Append one tool-calling turn to `messages` in place: the assistant's
--- own tool-call request (exactly as the API sent it, `raw_arguments`
--- and all — re-encoding a re-decoded table could reorder keys or
--- reformat numbers in a way that doesn't round-trip identically,
--- and the API doesn't care either way, so there's no reason to redo
--- work it already did), then one `role = 'tool'` message per result in
--- `tool_results` (`{ { id, ok, content }, ... }`, `mep.ai.agent`'s own
--- shape — `ok` only affects *how* the text reads to the model, OpenAI
--- has no separate "this was an error" field on a tool message).
local function openai_append_tool_turn(messages, parsed, tool_results)
  local calls = {}
  for _, call in ipairs(parsed.tool_calls) do
    calls[#calls + 1] = {
      id = call.id,
      type = 'function',
      ['function'] = { name = call.name, arguments = call.raw_arguments },
    }
  end
  messages[#messages + 1] = {
    role = 'assistant',
    content = parsed.text ~= '' and parsed.text or nil,
    tool_calls = calls,
  }
  for _, result in ipairs(tool_results) do
    messages[#messages + 1] = {
      role = 'tool',
      tool_call_id = result.id,
      content = (result.ok and result.content or ('Error: ' .. result.content)),
    }
  end
end

local function openai_headers(provider)
  local headers = {}
  if provider.api_key then
    headers[#headers + 1] = 'Authorization: Bearer ' .. provider.api_key
  end
  return headers
end

--- Anthropic's `system` is a top-level request field, not a `messages`
--- entry the way OpenAI's shape treats it — split it back out of
--- whatever `mep.ai.ai`/`mep.ai.agent` built as a uniform `{role,
--- content}` list.
local function split_system(messages)
  local system
  local rest = {}
  for _, message in ipairs(messages) do
    if message.role == 'system' then
      system = message.content
    else
      rest[#rest + 1] = message
    end
  end
  return system, rest
end

local function anthropic_tools(tools)
  if not tools then
    return nil
  end
  local out = {}
  for _, tool in ipairs(tools) do
    local properties, required = json_schema(tool.parameters)
    out[#out + 1] = {
      name = tool.name,
      description = tool.description,
      input_schema = { type = 'object', properties = properties, required = required },
    }
  end
  return out
end

local function anthropic_request(provider, messages, opts)
  opts = opts or {}
  local system, rest = split_system(messages)
  return {
    model = provider.model,
    max_tokens = provider.max_tokens or 4096,
    messages = rest,
    system = system,
    stream = opts.stream ~= false,
    temperature = provider.temperature,
    tools = anthropic_tools(opts.tools),
  }
end

--- Anthropic's stream is several `event: <type>` kinds (`message_start`,
--- `content_block_start`, `content_block_delta`, `message_delta`,
--- `message_stop`, `ping`); only `content_block_delta`'s own `data:`
--- payload carries text, shaped `{"delta":{"type":"text_delta","text":
--- "..."}}` — every other event's payload has no matching `delta.type`,
--- so this returns nil for them, same "nothing to insert" contract
--- `mep.ai.job` already treats a nil/empty delta as.
local function anthropic_delta(payload)
  return payload.delta and payload.delta.type == 'text_delta' and payload.delta.text or nil
end

--- A complete (non-streaming) Anthropic-shaped response body:
--- `{content:[{type:'text',text:...}, {type:'tool_use', id, name,
--- input}, ...]}` — `input` is already a decoded object (unlike
--- OpenAI's `function.arguments`, a JSON *string*), so no extra decode
--- step is needed here.
local function anthropic_parse_response(body)
  local text_parts = {}
  local tool_calls = {}
  for _, block in ipairs(body.content or {}) do
    if block.type == 'text' then
      text_parts[#text_parts + 1] = block.text
    elseif block.type == 'tool_use' then
      tool_calls[#tool_calls + 1 ] = { id = block.id, name = block.name, arguments = block.input or {} }
    end
  end
  return { text = table.concat(text_parts, ''), tool_calls = tool_calls }
end

--- Append one tool-calling turn to `messages` in place — Anthropic's own
--- shape: the assistant's turn is a single `content` array mixing its
--- own `text`/`tool_use` blocks (rebuilt here from `parsed`, since
--- Anthropic's `input` round-trips through `vim.json` cleanly, unlike
--- OpenAI's raw-string `arguments`), then a `user`-role message whose
--- own `content` is one `tool_result` block per entry in `tool_results`
--- (`is_error` is a real field in this shape, unlike OpenAI's).
local function anthropic_append_tool_turn(messages, parsed, tool_results)
  local content = {}
  if parsed.text ~= '' then
    content[#content + 1] = { type = 'text', text = parsed.text }
  end
  for _, call in ipairs(parsed.tool_calls) do
    content[#content + 1] = { type = 'tool_use', id = call.id, name = call.name, input = call.arguments }
  end
  messages[#messages + 1] = { role = 'assistant', content = content }

  local results = {}
  for _, result in ipairs(tool_results) do
    results[#results + 1] = {
      type = 'tool_result',
      tool_use_id = result.id,
      content = result.content,
      is_error = not result.ok or nil,
    }
  end
  messages[#messages + 1] = { role = 'user', content = results }
end

local function anthropic_headers(provider)
  local headers = { 'anthropic-version: 2023-06-01' }
  if provider.api_key then
    headers[#headers + 1] = 'x-api-key: ' .. provider.api_key
  end
  return headers
end

local KINDS = {
  openai = {
    request = openai_request,
    delta = openai_delta,
    headers = openai_headers,
    parse_response = openai_parse_response,
    append_tool_turn = openai_append_tool_turn,
  },
  anthropic = {
    request = anthropic_request,
    delta = anthropic_delta,
    headers = anthropic_headers,
    parse_response = anthropic_parse_response,
    append_tool_turn = anthropic_append_tool_turn,
  },
}

local function kind_of(provider)
  local kind = KINDS[provider.kind]
  assert(kind, 'mep.ai: unknown provider kind "' .. tostring(provider.kind) .. '"')
  return kind
end

--- The JSON-encodable request body for `provider`'s own kind, given a
--- uniform `{ { role = 'system'|'user'|'assistant'|'tool', content =
--- '...' }, ... }` message list (`mep.ai.ai`/`mep.ai.agent`'s own
--- shape, matching the OpenAI convention every provider here is at
--- least compatible with reading). `opts.stream` (default true) and
--- `opts.tools` (a `mep.ai.tools`-shaped list, default none) are both
--- optional — omitting `opts` entirely reproduces the exact request
--- `mep.ai.ai`'s own simple flows always built before tool-calling
--- existed.
function M.build_request(provider, messages, opts)
  return kind_of(provider).request(provider, messages, opts)
end

--- Extra `curl -H` header lines `provider`'s own kind needs beyond the
--- `Content-Type: application/json` `mep.ai.job` always sends — auth,
--- and (Anthropic only) the required API-version header.
function M.headers(provider)
  return kind_of(provider).headers(provider)
end

--- The text delta (if any) in one decoded SSE `data:` JSON payload for
--- `provider`'s own kind, or nil if this particular event carries none.
--- Streaming only — see `M.parse_response` for a non-streaming
--- (tool-calling-capable) turn.
function M.extract_delta(provider, payload)
  return kind_of(provider).delta(payload)
end

--- A complete, non-streaming response body (as `mep.ai.job.request`
--- hands back) parsed into `{ text, tool_calls = { { id, name,
--- arguments = <table> }, ... } }` — `text` is `''` (not nil) when the
--- turn is pure tool calls with no accompanying text, `tool_calls` is
--- `{}` (not nil) when the turn is pure text, so callers never need to
--- nil-check either field, only check `#tool_calls > 0`.
function M.parse_response(provider, body)
  return kind_of(provider).parse_response(body)
end

--- Append the assistant's tool-calling turn (`parsed`, as returned by
--- `M.parse_response`) plus its results (`tool_results`, `mep.ai.
--- agent`'s own `{ { id, ok, content }, ... }` shape — one entry per
--- `parsed.tool_calls`, in the same order) onto `messages` **in
--- place**, in whichever shape `provider`'s own kind needs for the next
--- request to make sense of them. Only meaningful to call when
--- `#parsed.tool_calls > 0`.
function M.append_tool_turn(provider, messages, parsed, tool_results)
  kind_of(provider).append_tool_turn(messages, parsed, tool_results)
end

return M

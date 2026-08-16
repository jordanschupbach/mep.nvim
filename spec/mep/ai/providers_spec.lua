local providers = require('mep.ai.providers')

-- mep.ai.tools' own neutral shape, standing in for a require('mep.ai.tools')
-- dependency this module deliberately doesn't have (pure request/response
-- shaping only) — see mep.ai.tools.registry for the real thing.
local TOOLS = {
  {
    name = 'read_file',
    description = 'Read a file',
    parameters = { { name = 'path', type = 'string', description = 'file path', required = true } },
  },
  {
    name = 'list_dir',
    description = 'List a directory',
    parameters = { { name = 'path', type = 'string', description = 'dir path', required = false } },
  },
}

describe('mep.ai.providers', function()
  describe('openai kind', function()
    local provider = { kind = 'openai', model = 'gpt-4o-mini', temperature = 0.5 }

    it('builds a Chat Completions-shaped request body', function()
      local messages = { { role = 'user', content = 'hi' } }
      assert.are.same({
        model = 'gpt-4o-mini',
        messages = messages,
        stream = true,
        temperature = 0.5,
      }, providers.build_request(provider, messages))
    end)

    it('adds an Authorization: Bearer header when api_key is set', function()
      assert.are.same({ 'Authorization: Bearer sk-abc' }, providers.headers({ kind = 'openai', api_key = 'sk-abc' }))
    end)

    it('adds no headers when api_key is unset (e.g. a local Ollama)', function()
      assert.are.same({}, providers.headers({ kind = 'openai' }))
    end)

    it('extracts the delta text from a choices[].delta.content payload', function()
      local payload = { choices = { { delta = { content = 'Hello' } } } }
      assert.are.equal('Hello', providers.extract_delta(provider, payload))
    end)

    it('returns nil when the payload has no delta content (e.g. the final chunk)', function()
      local payload = { choices = { { delta = {}, finish_reason = 'stop' } } }
      assert.is_nil(providers.extract_delta(provider, payload))
    end)

    it('returns nil for a payload with no choices at all', function()
      assert.is_nil(providers.extract_delta(provider, {}))
    end)

    it('sends stream = false when opts.stream = false (mep.ai.agent\'s own tool-calling turns)', function()
      local body = providers.build_request(provider, { { role = 'user', content = 'hi' } }, { stream = false })
      assert.is_false(body.stream)
    end)

    it('translates mep.ai.tools\' neutral shape into OpenAI\'s function-tool schema', function()
      local body = providers.build_request(provider, { { role = 'user', content = 'hi' } }, { tools = TOOLS })
      assert.are.same({
        {
          type = 'function',
          ['function'] = {
            name = 'read_file',
            description = 'Read a file',
            parameters = {
              type = 'object',
              properties = { path = { type = 'string', description = 'file path' } },
              required = { 'path' },
            },
          },
        },
        {
          type = 'function',
          ['function'] = {
            name = 'list_dir',
            description = 'List a directory',
            parameters = {
              type = 'object',
              properties = { path = { type = 'string', description = 'dir path' } },
              required = {},
            },
          },
        },
      }, body.tools)
    end)

    it('omits tools entirely when opts.tools is not given (unchanged from before tool-calling existed)', function()
      local body = providers.build_request(provider, { { role = 'user', content = 'hi' } })
      assert.is_nil(body.tools)
    end)

    it('parses a plain-text (no tool calls) response', function()
      local parsed = providers.parse_response(provider, {
        choices = { { message = { content = 'hello there' }, finish_reason = 'stop' } },
      })
      assert.are.equal('hello there', parsed.text)
      assert.are.same({}, parsed.tool_calls)
    end)

    it('parses a tool-calls response, decoding the JSON-string arguments', function()
      local parsed = providers.parse_response(provider, {
        choices = {
          {
            message = {
              content = '',
              tool_calls = {
                { id = 'call_1', ['function'] = { name = 'read_file', arguments = '{"path":"foo.txt"}' } },
              },
            },
            finish_reason = 'tool_calls',
          },
        },
      })
      assert.are.equal(1, #parsed.tool_calls)
      assert.are.equal('call_1', parsed.tool_calls[1].id)
      assert.are.equal('read_file', parsed.tool_calls[1].name)
      assert.are.same({ path = 'foo.txt' }, parsed.tool_calls[1].arguments)
    end)

    it('appends the assistant tool-call turn and one role=tool message per result', function()
      local messages = { { role = 'user', content = 'read foo.txt' } }
      local parsed = {
        text = '',
        tool_calls = { { id = 'call_1', name = 'read_file', arguments = { path = 'foo.txt' }, raw_arguments = '{"path":"foo.txt"}' } },
      }
      providers.append_tool_turn(provider, messages, parsed, { { id = 'call_1', ok = true, content = 'file contents' } })
      assert.are.equal(3, #messages)
      assert.are.same({
        role = 'assistant',
        content = nil,
        tool_calls = { { id = 'call_1', type = 'function', ['function'] = { name = 'read_file', arguments = '{"path":"foo.txt"}' } } },
      }, messages[2])
      assert.are.same({ role = 'tool', tool_call_id = 'call_1', content = 'file contents' }, messages[3])
    end)

    it('prefixes a failed tool result with "Error:" so the model can tell', function()
      local messages = {}
      local parsed = { text = '', tool_calls = { { id = 'call_1', name = 'run_command', arguments = {}, raw_arguments = '{}' } } }
      providers.append_tool_turn(provider, messages, parsed, { { id = 'call_1', ok = false, content = 'command not found' } })
      assert.matches('^Error: command not found$', messages[2].content) -- messages[1] is the assistant tool-call turn
    end)
  end)

  describe('anthropic kind', function()
    local provider = { kind = 'anthropic', model = 'claude-x', max_tokens = 2048 }

    it('splits a system message out into its own top-level field', function()
      local messages = {
        { role = 'system', content = 'be terse' },
        { role = 'user', content = 'hi' },
      }
      assert.are.same({
        model = 'claude-x',
        max_tokens = 2048,
        messages = { { role = 'user', content = 'hi' } },
        system = 'be terse',
        stream = true,
        temperature = nil,
      }, providers.build_request(provider, messages))
    end)

    it('defaults max_tokens to 4096 when the provider does not set one', function()
      local body = providers.build_request({ kind = 'anthropic', model = 'x' }, { { role = 'user', content = 'hi' } })
      assert.are.equal(4096, body.max_tokens)
    end)

    it('adds anthropic-version always, x-api-key only when api_key is set', function()
      assert.are.same({ 'anthropic-version: 2023-06-01' }, providers.headers({ kind = 'anthropic' }))
      assert.are.same(
        { 'anthropic-version: 2023-06-01', 'x-api-key: sk-ant' },
        providers.headers({ kind = 'anthropic', api_key = 'sk-ant' })
      )
    end)

    it('extracts text only from a content_block_delta-shaped text_delta payload', function()
      local payload = { delta = { type = 'text_delta', text = 'Hello' } }
      assert.are.equal('Hello', providers.extract_delta(provider, payload))
    end)

    it('returns nil for a non-text_delta event (message_start, message_stop, ...)', function()
      assert.is_nil(providers.extract_delta(provider, { type = 'message_start', message = {} }))
      assert.is_nil(providers.extract_delta(provider, { delta = { type = 'input_json_delta', partial_json = '{}' } }))
    end)

    it('sends stream = false when opts.stream = false', function()
      local body = providers.build_request(provider, { { role = 'user', content = 'hi' } }, { stream = false })
      assert.is_false(body.stream)
    end)

    it('translates mep.ai.tools\' neutral shape into Anthropic\'s input_schema tool shape', function()
      local body = providers.build_request(provider, { { role = 'user', content = 'hi' } }, { tools = TOOLS })
      assert.are.same({
        {
          name = 'read_file',
          description = 'Read a file',
          input_schema = {
            type = 'object',
            properties = { path = { type = 'string', description = 'file path' } },
            required = { 'path' },
          },
        },
        {
          name = 'list_dir',
          description = 'List a directory',
          input_schema = {
            type = 'object',
            properties = { path = { type = 'string', description = 'dir path' } },
            required = {},
          },
        },
      }, body.tools)
    end)

    it('parses a plain-text (no tool calls) response', function()
      local parsed = providers.parse_response(provider, {
        content = { { type = 'text', text = 'hello there' } },
        stop_reason = 'end_turn',
      })
      assert.are.equal('hello there', parsed.text)
      assert.are.same({}, parsed.tool_calls)
    end)

    it('parses a tool_use response — input is already a decoded table, no extra JSON-decode needed', function()
      local parsed = providers.parse_response(provider, {
        content = {
          { type = 'text', text = 'let me check' },
          { type = 'tool_use', id = 'toolu_1', name = 'read_file', input = { path = 'foo.txt' } },
        },
        stop_reason = 'tool_use',
      })
      assert.are.equal('let me check', parsed.text)
      assert.are.equal(1, #parsed.tool_calls)
      assert.are.same({ id = 'toolu_1', name = 'read_file', arguments = { path = 'foo.txt' } }, parsed.tool_calls[1])
    end)

    it('appends the assistant content-block turn and a user tool_result turn', function()
      local messages = { { role = 'user', content = 'read foo.txt' } }
      local parsed = { text = '', tool_calls = { { id = 'toolu_1', name = 'read_file', arguments = { path = 'foo.txt' } } } }
      providers.append_tool_turn(provider, messages, parsed, { { id = 'toolu_1', ok = true, content = 'file contents' } })
      assert.are.equal(3, #messages)
      assert.are.same({
        role = 'assistant',
        content = { { type = 'tool_use', id = 'toolu_1', name = 'read_file', input = { path = 'foo.txt' } } },
      }, messages[2])
      assert.are.same({
        role = 'user',
        content = { { type = 'tool_result', tool_use_id = 'toolu_1', content = 'file contents', is_error = nil } },
      }, messages[3])
    end)

    it('sets is_error = true on a failed tool result, a real field in this shape', function()
      local messages = {}
      local parsed = { text = '', tool_calls = { { id = 'toolu_1', name = 'run_command', arguments = {} } } }
      providers.append_tool_turn(provider, messages, parsed, { { id = 'toolu_1', ok = false, content = 'boom' } })
      assert.is_true(messages[2].content[1].is_error)
    end)

    it('includes the assistant\'s own text alongside tool_use blocks when both are present', function()
      local messages = {}
      local parsed = { text = 'checking now', tool_calls = { { id = 'toolu_1', name = 'read_file', arguments = {} } } }
      providers.append_tool_turn(provider, messages, parsed, { { id = 'toolu_1', ok = true, content = 'x' } })
      assert.are.same({ type = 'text', text = 'checking now' }, messages[1].content[1])
    end)
  end)

  describe('unknown kind', function()
    it('errors from build_request/headers/extract_delta alike', function()
      local provider = { kind = 'not-a-real-kind' }
      assert.has_error(function()
        providers.build_request(provider, {})
      end)
      assert.has_error(function()
        providers.headers(provider)
      end)
      assert.has_error(function()
        providers.extract_delta(provider, {})
      end)
      assert.has_error(function()
        providers.parse_response(provider, {})
      end)
      assert.has_error(function()
        providers.append_tool_turn(provider, {}, { text = '', tool_calls = {} }, {})
      end)
    end)
  end)
end)

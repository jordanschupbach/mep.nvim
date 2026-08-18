--- The tool-calling orchestration loop behind visual-mode `gk` (see
--- `mep.ai.ai`'s own `M.setup` for the keymap wiring) — where `mep.ai.
--- send`/`send_selection` are each one fire-and-forget request,
--- `M.start` here begins a genuinely multi-turn session: request, maybe
--- some tool calls (each gated by an explicit permission decision
--- routed through `mep.ai.panel`), continue with their results, repeat
--- until the model stops asking for tools, then sit idle waiting for
--- either a free-text reply (typed into the panel, `mep.ai.panel`'s own
--- `i` keymap) or `M.cancel()`.
---
--- A **session** (the shape every function here and every `mep.ai.
--- panel` render call passes around) is a plain table:
---   { bufnr, win, scope,       -- scope: {start_line, end_line} (1-indexed,
---                              -- inclusive) for a visual-mode call, nil
---                              -- for a whole-buffer one
---     provider, tools_enabled, -- resolved provider; mep.ai.tools-shaped
---                              -- list of the tools this session may call
---     messages,                -- the raw API message list (mep.ai.providers'
---                              -- own {role, content} shape)
---     transcript,              -- { {role, text}, ... } -- mep.ai.panel's
---                              -- own rendering input; role one of 'user',
---                              -- 'assistant', 'tool_call', 'tool_result',
---                              -- 'error', 'info'
---     permissions,             -- tool_name -> true, "always allow" grants
---                              -- (risk='read' tools only -- see mep.ai.tools)
---     pending,                 -- nil, or { kind='permission', tool_name,
---                              -- description, allow_always, on_decide(decision) }
---                              -- while waiting on a permission decision
---                              -- ('allow'|'always'|'deny')
---     busy,                    -- true while a request is in flight
---     job,                     -- the in-flight mep.ai.job.request handle, or nil
---     on_reply(text) }         -- called by mep.ai.panel when the user types
---                              -- a follow-up message
---
--- Only one session is ever live at a time (mep.ai.panel is itself a
--- singleton panel — realistically only one agent conversation is
--- useful to have visibly running at once); starting a new one cancels
--- whatever the previous one had in flight.
---
--- Editing: deliberately no dedicated "write/replace buffer text" tool
--- (`mep.ai.tools` ships exactly three: `read_file`, `list_dir`,
--- `run_command` -- read-only plus shell, not read-only plus a bespoke
--- editing primitive). An edit happens the same way a human collaborator
--- editing over your shoulder would do it: the agent runs a real shell
--- command against the file on disk (permission-gated exactly like any
--- other `run_command` call, every single time -- see `mep.ai.tools`'s
--- own `risk = 'exec'` never getting an "always allow"), and `M.
--- checktime` below picks the change back up into the live buffer
--- afterwards, the same as if you'd edited the file in another terminal
--- and come back to Neovim.
local config = require('mep.ai.config')
local job_mod = require('mep.ai.job')
local providers = require('mep.ai.providers')
local tools_mod = require('mep.ai.tools')
local panel = require('mep.ai.panel')

local M = {}

-- The one live session, if any -- see this module's own header comment
-- for why a singleton (mep.ai.panel is one too).
local current_session = nil

local function transcript_add(session, role, text)
  session.transcript[#session.transcript + 1] = { role = role, text = text }
end

--- Re-read `session.bufnr`'s file from disk if it changed underneath the
--- buffer and the buffer itself has no unsaved local edits -- Vim's own
--- `:checktime` semantics, deliberately: if there *are* unsaved local
--- edits, this warns instead of clobbering them, exactly like running it
--- by hand would. Called after every tool result lands, since a
--- `run_command` result is the only way this session's own tool set can
--- ever change a file (see this module's own header comment on editing).
local function checktime(session)
  if vim.api.nvim_buf_is_valid(session.bufnr) then
    pcall(vim.cmd, 'checktime ' .. session.bufnr)
  end
end

--- A short, human-readable one-liner describing `call` for the
--- permission prompt -- the exact command for `run_command` (the whole
--- reason a permission prompt exists at all: knowing precisely what's
--- about to run before saying yes), a plain JSON dump of the arguments
--- for anything else.
local function describe_call(call)
  if call.name == 'run_command' then
    return 'Run: ' .. tostring(call.arguments.command)
  end
  return call.name .. ' ' .. vim.json.encode(call.arguments)
end

--- The real, runnable `mep.ai.tools.registry` entry (with its own `run`/
--- `risk`, neither of which `session.tools_enabled` carries — that
--- list is deliberately the neutral, provider-facing shape `mep.ai.
--- providers` needs, name/description/parameters only) for `name`, but
--- only if it's actually one of `session.tools_enabled` — a tool this
--- session never offered (a stale/hallucinated name from the model)
--- doesn't get run just because it happens to exist in the registry.
local function tool_by_name(session, name)
  for _, tool in ipairs(session.tools_enabled) do
    if tool.name == name then
      return tools_mod.registry[name]
    end
  end
  return nil
end

local run_turn

--- Run every tool call in `parsed.tool_calls` in sequence (one at a
--- time, not concurrently -- each may need a real permission decision
--- from the user in between, so there is no meaningful "run them all at
--- once" here), gating each on `session.permissions`/an explicit
--- `session.pending` prompt exactly as this module's own header comment
--- describes, then calls `on_done(tool_results)` (`mep.ai.providers.
--- append_tool_turn`'s own `{ {id, ok, content}, ... }` shape) once
--- every call has settled.
local function execute_tool_calls(session, parsed, on_done)
  local results = {}
  local i = 0

  local function next_call()
    i = i + 1
    local call = parsed.tool_calls[i]
    if not call then
      on_done(results)
      return
    end

    local tool = tool_by_name(session, call.name)
    if not tool then
      results[#results + 1] = { id = call.id, ok = false, content = 'unknown or disabled tool "' .. call.name .. '"' }
      next_call()
      return
    end

    local function run_now()
      transcript_add(session, 'tool_call', describe_call(call))
      panel.render(session)
      tool.run(call.arguments, function(ok, content)
        results[#results + 1] = { id = call.id, ok = ok, content = content }
        transcript_add(session, 'tool_result', content)
        checktime(session)
        panel.render(session)
        next_call()
      end)
    end

    if tool.risk == 'read' and session.permissions[call.name] then
      run_now()
      return
    end

    session.pending = {
      kind = 'permission',
      tool_name = call.name,
      description = describe_call(call),
      allow_always = tool.risk == 'read',
      on_decide = function(decision)
        session.pending = nil
        if decision == 'deny' then
          results[#results + 1] = { id = call.id, ok = false, content = 'denied by user' }
          transcript_add(session, 'info', 'Denied: ' .. describe_call(call))
          panel.render(session)
          next_call()
          return
        end
        if decision == 'always' then
          session.permissions[call.name] = true
        end
        run_now()
      end,
    }
    panel.render(session)
  end

  next_call()
end

--- One full request/response step of `session`'s own conversation:
--- send `session.messages` (with `session.tools_enabled` on offer),
--- render whatever text came back, and — only if the model actually
--- asked for tools this turn — gate/run them (`execute_tool_calls`),
--- append the results (`mep.ai.providers.append_tool_turn`), and
--- recurse for the next turn. Returns to idle (waiting on `session.
--- on_reply`) the moment a turn comes back with zero tool calls.
function run_turn(session)
  session.busy = true
  panel.render(session)

  session.job = job_mod.request(session.provider, session.messages, session.tools_enabled, function(err, parsed)
    session.job = nil
    if err then
      session.busy = false
      transcript_add(session, 'error', err)
      panel.render(session)
      return
    end

    if parsed.text ~= '' then
      transcript_add(session, 'assistant', parsed.text)
    end

    if #parsed.tool_calls == 0 then
      session.busy = false
      panel.render(session)
      return
    end

    execute_tool_calls(session, parsed, function(tool_results)
      providers.append_tool_turn(session.provider, session.messages, parsed, tool_results)
      run_turn(session)
    end)
  end)
end

--- `{ name, description, parameters }` (mep.ai.providers' own expected
--- shape) for every name in `config.options.tools` that's actually
--- registered in `mep.ai.tools.registry` -- silently skipping any name
--- that isn't (a typo'd entry in a user's own `setup({ai = {tools =
--- {...}}})` shouldn't hard-error, just offer one fewer tool than asked
--- for).
local function enabled_tools()
  local out = {}
  for _, name in ipairs(config.options.tools) do
    local tool = tools_mod.registry[name]
    if tool then
      out[#out + 1] = { name = name, description = tool.description, parameters = tool.parameters }
    end
  end
  return out
end

--- Start a new agent session, replacing whatever one was live before
--- (cancelling its in-flight request first, if any -- see `M.cancel`).
--- `opts.bufnr`/`opts.win` default to the current buffer/window.
--- `opts.scope` (`{start_line, end_line}`, 1-indexed inclusive), when
--- given, is a visual-mode call -- the agent is told about it as its
--- specific editable target, on top of (not instead of) the whole
--- buffer's own content, which is always included as context regardless
--- (see this module's own header comment, and the design goal it
--- traces back to: "still by default send the current buffer as
--- context"). `opts.instructions`, when given (the `gk` popup's own
--- use), is sent as an explicit instruction; without it (a plain
--- `:MepAiAgent` call), the agent works from the buffer/block's own
--- content and its own judgment alone. `opts.provider` defaults to
--- `config.options.provider`.
--- Opens (or re-targets) `mep.ai.panel` on the new session and kicks
--- off its first turn. Returns the new session, or nil (after a
--- notification) if no provider is ready to use.
function M.start(opts)
  opts = opts or {}
  if current_session and current_session.job then
    current_session.job.kill()
  end

  local ai = require('mep.ai')
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  local provider = ai.resolve_provider(opts.provider)
  if not provider then
    return nil
  end

  local scope = opts.scope
  local buffer_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local filetype = vim.bo[bufnr].filetype
  local filename = vim.api.nvim_buf_get_name(bufnr)

  local context_parts = {
    'File: ' .. (filename ~= '' and filename or '(unnamed buffer)'),
  }
  if filetype ~= '' then
    context_parts[#context_parts + 1] = 'Filetype: ' .. filetype
  end
  if opts.instructions then
    context_parts[#context_parts + 1] = 'Instructions: ' .. opts.instructions
  end
  if scope then
    local block = table.concat(vim.api.nvim_buf_get_lines(bufnr, scope[1] - 1, scope[2], false), '\n')
    context_parts[#context_parts + 1] =
      string.format('Editable target -- lines %d-%d of the file above:\n%s', scope[1], scope[2], block)
  end
  context_parts[#context_parts + 1] = 'Full buffer contents, for context:\n' .. buffer_text

  local session = {
    bufnr = bufnr,
    win = win,
    scope = scope,
    provider = provider,
    tools_enabled = enabled_tools(),
    messages = {
      { role = 'system', content = config.options.tool_agent_system_prompt },
      { role = 'user', content = table.concat(context_parts, '\n\n') },
    },
    transcript = {},
    permissions = {},
    pending = nil,
    busy = false,
    job = nil,
  }
  transcript_add(session, 'user', opts.instructions or (scope and 'Look at the selected block and the buffer.' or 'Look at the buffer.'))

  session.on_reply = function(text)
    if session.busy or session.pending then
      return
    end
    session.messages[#session.messages + 1] = { role = 'user', content = text }
    transcript_add(session, 'user', text)
    run_turn(session)
  end

  current_session = session
  panel.open(session)
  run_turn(session)
  return session
end

--- Whether the current session has a request in flight -- read by
--- `mep.ai.ai`'s own unified cancel keymap to decide between this and
--- `mep.ai.ai.cancel()` without a spurious "nothing in flight"
--- notification from whichever of the two wasn't actually running.
function M.is_busy()
  return current_session ~= nil and current_session.job ~= nil
end

--- Cancel the current session's in-flight request, if any -- a no-op
--- (with a notification) otherwise. The session itself stays open
--- (still showing its transcript so far, still able to take a reply),
--- same as `mep.ai.cancel` leaves whatever streamed in before a plain
--- `M.send` was cancelled.
function M.cancel()
  if not current_session or not current_session.job then
    vim.notify('mep.ai: no agent request in flight', vim.log.levels.INFO)
    return
  end
  current_session.job.kill()
  current_session.job = nil
  current_session.busy = false
  transcript_add(current_session, 'info', 'Cancelled')
  panel.render(current_session)
end

--- Test/dev-only: drop the current session (killing its in-flight job,
--- if any) and reset `mep.ai.panel` alongside it, so the next `M.start`
--- (in a fresh spec, or a fresh real session) begins from a clean slate.
function M._reset()
  if current_session and current_session.job then
    current_session.job.kill()
  end
  current_session = nil
  panel._reset()
end

return M

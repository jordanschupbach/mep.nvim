--- The single active debug session (like `mep.ai`'s single in-flight
--- job, or `mep.org.clock`'s single open clock — only one debuggee at a
--- time): owns the DAP init handshake (`initialize` -> `launch`/`attach`
--- -> wait for `initialized` -> push breakpoints -> `configurationDone`),
--- tracks the current thread/stack/scopes/variables as `stopped` events
--- arrive, and exposes the control actions (`continue`/`step_over`/
--- `step_into`/`step_out`/`terminate`). `mep.dap.sidebar`/`mep.dap.repl`
--- render this module's own state; `M.subscribe` is how they hear about
--- changes to it without polling.
local client_mod = require('mep.dap.client')
local adapters = require('mep.dap.adapters')
local config = require('mep.dap.config')
local breakpoints = require('mep.dap.breakpoints')

local M = {}

M.client = nil
M.status = 'inactive' -- inactive | initializing | running | stopped | terminated
M.capabilities = {}
M.threads = {}
M.current_thread_id = nil
M.stack_frames = {}
M.current_frame_id = nil
M.scopes = {}
M.variables = {} -- variablesReference -> list of variable tables

local stopped_ns = vim.api.nvim_create_namespace('mep_dap_stopped')
local stopped_bufnr = nil
local listeners = {}

--- Give MepDapStopped a visible default if nothing else already has —
--- same `default = true` reasoning as `mep.dap.breakpoints.define_
--- default_hl`.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, 'MepDapStopped', { link = 'DiagnosticWarn', default = true })
end
M.define_default_hl()

--- Register `fn(kind, data)` for every session change worth rendering:
--- `'initialized'`, `'stopped'` (data: the event body), `'continued'`,
--- `'output'` (data: the event body — `.category`/`.output`),
--- `'terminated'`/`'exited'`, `'stack_updated'` (data: `M.stack_frames`),
--- `'scopes_updated'` (data: `M.scopes`), `'variables_updated'` (data:
--- the `variablesReference` that changed — read the values back from
--- `M.variables[ref]`).
function M.subscribe(fn)
  listeners[#listeners + 1] = fn
end

local function emit(kind, data)
  for _, fn in ipairs(listeners) do
    fn(kind, data)
  end
end

--- `mep.dap.adapters.registry[name]` merged with `config.options.
--- adapters[name]` (the override winning) — same "curated entry,
--- optionally overridden" pattern `mep.lsp`'s own server resolution
--- uses. `nil` if `name` isn't in either.
local function resolve_adapter(name)
  local curated = adapters.registry[name]
  local override = config.options.adapters[name]
  if not curated and not override then
    return nil
  end
  return vim.tbl_deep_extend('force', curated or {}, override or {})
end
M.resolve_adapter = resolve_adapter

function M.is_active()
  return M.client ~= nil and M.client:is_running()
end

local function clear_stopped_sign()
  if stopped_bufnr and vim.api.nvim_buf_is_valid(stopped_bufnr) then
    vim.api.nvim_buf_clear_namespace(stopped_bufnr, stopped_ns, 0, -1)
  end
  stopped_bufnr = nil
end

--- Send `setBreakpoints` for every file `mep.dap.breakpoints` currently
--- has recorded, then call `done()` once every response is back (or
--- immediately if there's nothing to send) — the handshake step between
--- the adapter's own `initialized` event and `configurationDone`.
local function send_all_breakpoints(done)
  local all = breakpoints.all()
  if #all == 0 then
    if done then
      done()
    end
    return
  end
  local remaining = #all
  for _, entry in ipairs(all) do
    local bps = {}
    for _, lnum in ipairs(entry.lnums) do
      bps[#bps + 1] = { line = lnum }
    end
    M.client:request('setBreakpoints', { source = { path = entry.path }, breakpoints = bps }, function()
      remaining = remaining - 1
      if remaining == 0 and done then
        done()
      end
    end)
  end
end

--- Push just `path`'s current breakpoints (used for a live toggle while
--- a session is already running — see the `breakpoints.on_change`
--- subscription below).
local function send_breakpoints_for(path, lnums)
  local bps = {}
  for _, lnum in ipairs(lnums) do
    bps[#bps + 1] = { line = lnum }
  end
  M.client:request('setBreakpoints', { source = { path = path }, breakpoints = bps }, function() end)
end

breakpoints.on_change(function(path, lnums)
  if M.is_active() and M.status ~= 'initializing' then
    send_breakpoints_for(path, lnums)
  end
end)

--- Open (or focus) the top stack frame's source file and mark its line,
--- once `refresh_stack` gets a frame back — real editor UX for "you're
--- stopped here", not just data in a sidebar.
local function jump_to_current_frame()
  local frame = M.stack_frames[1]
  if not frame or not frame.source or not frame.source.path then
    return
  end
  vim.schedule(function()
    local ok = pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(frame.source.path))
    if not ok then
      return
    end
    clear_stopped_sign()
    local bufnr = vim.api.nvim_get_current_buf()
    stopped_bufnr = bufnr
    local sign = config.options.signs.stopped
    local lnum = frame.line or 1
    pcall(vim.api.nvim_buf_set_extmark, bufnr, stopped_ns, lnum - 1, 0, {
      sign_text = sign.text,
      sign_hl_group = sign.hl,
    })
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max(0, (frame.column or 1) - 1) })
  end)
end

--- `variablesReference` values from a `variables`/`scopes` response are
--- `0` for "this has no children" — never worth requesting.
function M.refresh_variables(var_ref)
  if not M.client or not var_ref or var_ref == 0 then
    return
  end
  M.client:request('variables', { variablesReference = var_ref }, function(resp)
    if resp.success then
      M.variables[var_ref] = (resp.body and resp.body.variables) or {}
      emit('variables_updated', var_ref)
    end
  end)
end

function M.refresh_scopes()
  if not M.client or not M.current_frame_id then
    return
  end
  M.client:request('scopes', { frameId = M.current_frame_id }, function(resp)
    if resp.success then
      M.scopes = (resp.body and resp.body.scopes) or {}
      emit('scopes_updated', M.scopes)
      for _, scope in ipairs(M.scopes) do
        M.refresh_variables(scope.variablesReference)
      end
    end
  end)
end

--- Request the current thread's call stack, take its top frame as
--- `M.current_frame_id`, then cascade into `refresh_scopes` and jumping
--- the editor to that frame's source location.
function M.refresh_stack()
  if not M.client or not M.current_thread_id then
    return
  end
  M.client:request('stackTrace', { threadId = M.current_thread_id }, function(resp)
    if resp.success then
      M.stack_frames = (resp.body and resp.body.stackFrames) or {}
      M.current_frame_id = M.stack_frames[1] and M.stack_frames[1].id or nil
      emit('stack_updated', M.stack_frames)
      M.refresh_scopes()
      jump_to_current_frame()
    end
  end)
end

local function on_event(event, body)
  if event == 'initialized' then
    send_all_breakpoints(function()
      M.client:request('configurationDone', {}, function() end)
      M.status = 'running'
      emit('initialized')
    end)
  elseif event == 'stopped' then
    M.status = 'stopped'
    M.current_thread_id = body and body.threadId
    emit('stopped', body)
    M.refresh_stack()
  elseif event == 'continued' then
    M.status = 'running'
    clear_stopped_sign()
    emit('continued', body)
  elseif event == 'terminated' or event == 'exited' then
    M.status = 'terminated'
    clear_stopped_sign()
    emit(event, body)
  else
    -- 'output', 'thread', and anything else this session doesn't need
    -- to react to structurally still reach subscribers (mep.dap.repl
    -- wants 'output'; a sidebar could want 'thread') — just not handled
    -- specially here.
    emit(event, body)
  end
end

local function on_exit(code)
  M.status = 'inactive'
  clear_stopped_sign()
  emit('exited', code)
end

--- `initialize` -> `launch`/`attach` -> (adapter's own `initialized`
--- event drives the rest, see `on_event` above). A no-op (with a
--- notification) if a session is already active, or `adapter_name`
--- isn't resolvable, or its `cmd[1]` isn't on `PATH`.
local function start(adapter_name, request_type, args)
  if M.is_active() then
    vim.notify('mep.dap: a session is already active', vim.log.levels.WARN)
    return
  end
  local adapter = resolve_adapter(adapter_name)
  if not adapter then
    vim.notify('mep.dap: unknown adapter ' .. tostring(adapter_name), vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable(adapter.cmd[1]) ~= 1 then
    vim.notify('mep.dap: ' .. tostring(adapter.cmd[1]) .. ' not found on PATH', vim.log.levels.ERROR)
    return
  end

  M.status = 'initializing'
  M.threads, M.stack_frames, M.scopes, M.variables = {}, {}, {}, {}
  M.current_thread_id, M.current_frame_id = nil, nil

  M.client = client_mod.new({ cmd = adapter.cmd, on_event = on_event, on_exit = on_exit })
  M.client:request('initialize', {
    clientID = 'mep.nvim',
    adapterID = adapter_name,
    linesStartAt1 = true,
    columnsStartAt1 = true,
    pathFormat = 'path',
  }, function(resp)
    if not resp.success then
      vim.notify('mep.dap: initialize failed: ' .. tostring(resp.message), vim.log.levels.ERROR)
      M.terminate()
      return
    end
    M.capabilities = resp.body or {}
    M.client:request(request_type, args or {}, function(req_resp)
      if not req_resp.success then
        vim.notify('mep.dap: ' .. request_type .. ' failed: ' .. tostring(req_resp.message), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Start a session against adapter `adapter_name` (a name in
--- `mep.dap.adapters.registry` or `config.options.adapters`), sending
--- `args` as the DAP `launch` request's own arguments (adapter-specific
--- — typically at least `{ program = ... }`).
function M.launch(adapter_name, args)
  start(adapter_name, 'launch', args)
end

--- Like `M.launch`, but sends an `attach` request instead — `args` is
--- typically `{ processId = ... }` or a port, again adapter-specific.
function M.attach(adapter_name, args)
  start(adapter_name, 'attach', args)
end

--- Prompt (`vim.ui.select` for the adapter, `vim.ui.input` for a program
--- path) and `M.launch` with the answers. A cancelled prompt launches
--- nothing.
function M.launch_interactive()
  local names = adapters.names()
  for name in pairs(config.options.adapters) do
    if not vim.tbl_contains(names, name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  vim.ui.select(names, { prompt = 'mep.dap: adapter' }, function(choice)
    if not choice then
      return
    end
    vim.ui.input({ prompt = 'mep.dap: program: ', default = vim.fn.expand('%:p'), completion = 'file' }, function(program)
      if program == nil then
        return
      end
      M.launch(choice, { program = program })
    end)
  end)
end

local function require_thread(fn_name)
  if not M.client or not M.current_thread_id then
    vim.notify('mep.dap: no stopped thread to ' .. fn_name, vim.log.levels.WARN)
    return false
  end
  return true
end

function M.continue()
  if not require_thread('continue') then
    return
  end
  M.client:request('continue', { threadId = M.current_thread_id }, function() end)
end

function M.step_over()
  if not require_thread('step over') then
    return
  end
  M.client:request('next', { threadId = M.current_thread_id }, function() end)
end

function M.step_into()
  if not require_thread('step into') then
    return
  end
  M.client:request('stepIn', { threadId = M.current_thread_id }, function() end)
end

function M.step_out()
  if not require_thread('step out') then
    return
  end
  M.client:request('stepOut', { threadId = M.current_thread_id }, function() end)
end

--- Evaluate `expression` in the current frame's context (the REPL/watch
--- use case). `callback(response)` gets the raw DAP response
--- (`{ success, body = { result, ... } }`). A no-op (synthetic failure
--- callback) with no active session.
function M.evaluate(expression, callback)
  if not M.client then
    if callback then
      callback({ success = false, message = 'no active session' })
    end
    return
  end
  M.client:request(
    'evaluate',
    { expression = expression, frameId = M.current_frame_id, context = 'repl' },
    callback
  )
end

--- Disconnect (asking the adapter to terminate the debuggee) and kill
--- the adapter process. Safe to call even if nothing is active.
function M.terminate()
  if M.client then
    if M.client:is_running() then
      M.client:request('disconnect', { terminateDebuggee = true }, function() end)
    end
    M.client:close()
  end
  clear_stopped_sign()
  M.client = nil
  M.status = 'inactive'
end

--- Test/dev-only: drop every cached session/state field (killing a live
--- adapter first, same reasoning as `mep.ai._reset`) so a fresh session
--- (or the next spec file sharing this busted run) starts clean.
function M._reset()
  M.terminate()
  M.threads, M.stack_frames, M.scopes, M.variables = {}, {}, {}, {}
  M.current_thread_id, M.current_frame_id = nil, nil
  M.capabilities = {}
  listeners = {}
end

return M

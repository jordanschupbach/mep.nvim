--- A single DAP session's transport: spawns an adapter process and
--- speaks the Debug Adapter Protocol over its stdio (mep.dap.protocol's
--- Content-Length framing). Raw `vim.fn.jobstart`, not mep.core.job —
--- that module's line-buffered feeder assumes "whatever's between
--- newlines is one meaningful unit", which doesn't hold for a length-
--- prefixed binary framing where the only thing that reliably delimits
--- one message from the next is the byte count in its own header (see
--- mep.dap.protocol's own header comment).
local protocol = require('mep.dap.protocol')

local Client = {}
Client.__index = Client

--- opts: `{ cmd = {...}, cwd = ..., on_event = function(event, body) end,
--- on_exit = function(code) end }`. `on_event` fires for every adapter
--- event (`stopped`/`output`/`initialized`/`terminated`/...); `on_exit`
--- fires once, when the adapter process itself exits (also firing every
--- still-pending request's callback first, with a synthetic failure
--- response, so nothing waits forever).
function Client.new(opts)
  local self = setmetatable({}, Client)
  self.seq = 0
  self.pending = {}
  self.buffer = ''
  self.on_event = opts.on_event
  self.on_exit = opts.on_exit

  self.job_id = vim.fn.jobstart(opts.cmd, {
    cwd = opts.cwd,
    on_stdout = function(_, data)
      self:_feed(data)
    end,
    on_exit = function(_, code)
      self:_handle_exit(code)
    end,
  })

  return self
end

--- Whether the adapter process is still alive (a freshly-failed spawn —
--- `jobstart` returning <= 0 — counts as not running from the start).
function Client:is_running()
  return self.job_id ~= nil and self.job_id > 0
end

function Client:_feed(data)
  if not data then
    return
  end
  self.buffer = self.buffer .. table.concat(data, '\n')
  local messages
  messages, self.buffer = protocol.parse_messages(self.buffer)
  for _, msg in ipairs(messages) do
    self:_dispatch(msg)
  end
end

function Client:_dispatch(msg)
  if msg.type == 'response' then
    local cb = self.pending[msg.request_seq]
    self.pending[msg.request_seq] = nil
    if cb then
      cb(msg)
    end
  elseif msg.type == 'event' and self.on_event then
    self.on_event(msg.event, msg.body)
  end
  -- Reverse requests (type == 'request', adapter -> client — e.g.
  -- 'runInTerminal'/'startDebugging') aren't answered: out of scope for
  -- the curated, already-running-in-Neovim's-own-terminal adapters this
  -- client targets (see mep.dap.adapters' own header comment).
end

function Client:_handle_exit(code)
  self.job_id = nil
  local pending = self.pending
  self.pending = {}
  for _, cb in pairs(pending) do
    cb({ success = false, message = 'adapter exited' })
  end
  if self.on_exit then
    self.on_exit(code)
  end
end

--- Send a DAP request. `callback(response)` (optional) is called once
--- with the decoded response message (`{ success, body, message, ... }`)
--- when a matching `response` arrives — synchronously, with a synthetic
--- failure, if the adapter isn't running at all.
function Client:request(command, arguments, callback)
  if not self:is_running() then
    if callback then
      callback({ success = false, message = 'adapter not running' })
    end
    return
  end
  self.seq = self.seq + 1
  local seq = self.seq
  if callback then
    self.pending[seq] = callback
  end
  vim.fn.chansend(self.job_id, protocol.encode({ seq = seq, type = 'request', command = command, arguments = arguments }))
end

--- Kill the adapter process. `_handle_exit` (via the job's own on_exit)
--- does the actual state teardown, so behavior is identical whether the
--- adapter is stopped this way or exits on its own.
function Client:close()
  if self:is_running() then
    pcall(vim.fn.jobstop, self.job_id)
  end
end

return Client

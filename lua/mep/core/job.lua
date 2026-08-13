--- Thin async job runner built on `vim.fn.jobstart` (no external Lua deps).
--- Streams stdout/stderr line-by-line so callers (e.g. picker sources) can
--- react to output as it arrives instead of waiting for the process to exit.
local M = {}

local function make_line_feeder(on_line)
  local pending = ''
  return function(data)
    if not data then
      return
    end
    data[1] = pending .. data[1]
    pending = table.remove(data) or ''
    for _, line in ipairs(data) do
      if on_line then
        on_line(line)
      end
    end
  end, function()
    if pending ~= '' and on_line then
      on_line(pending)
    end
  end
end

--- Spawn `opts.cmd` (a list-style table, e.g. `{ 'rg', '--files' }`).
--- opts: { cmd, cwd, env, on_stdout(line), on_stderr(line), on_exit(code) }
--- Returns a handle: `{ id, kill = function() end }`.
function M.spawn(opts)
  assert(type(opts.cmd) == 'table', 'core.job.spawn: opts.cmd must be a list-like table')

  local feed_stdout, flush_stdout = make_line_feeder(opts.on_stdout)
  local feed_stderr, flush_stderr = make_line_feeder(opts.on_stderr)

  local id = vim.fn.jobstart(opts.cmd, {
    cwd = opts.cwd,
    env = opts.env,
    on_stdout = function(_, data)
      feed_stdout(data)
    end,
    on_stderr = function(_, data)
      feed_stderr(data)
    end,
    on_exit = function(_, code)
      flush_stdout()
      flush_stderr()
      if opts.on_exit then
        opts.on_exit(code)
      end
    end,
  })

  if id <= 0 then
    if opts.on_exit then
      vim.schedule(function()
        opts.on_exit(-1)
      end)
    end
    return { id = id, kill = function() end }
  end

  return {
    id = id,
    kill = function()
      pcall(vim.fn.jobstop, id)
    end,
  }
end

return M

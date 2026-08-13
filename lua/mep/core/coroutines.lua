--- Minimal async/await helpers built on native Lua coroutines.
---
--- A "thunk" is a function of the shape `function(step) ... end` that must
--- arrange to call `step(...)` exactly once, asynchronously, with the result
--- of the operation it represents. `M.wrap` turns an ordinary callback-style
--- function into something that produces thunks; `M.await` suspends the
--- current coroutine until a thunk calls back; `M.run` drives a function
--- body full of `await` calls to completion.
local M = {}

--- Wrap a callback-style function (callback is the last positional arg) so
--- it can be used with `M.await`.
---   local read = M.wrap(vim.loop.fs_read)
---   local data = M.await(read(fd, size, offset))
function M.wrap(fn)
  return function(...)
    local args = { ... }
    local nargs = select('#', ...)
    return function(step)
      args[nargs + 1] = step
      fn(unpack(args, 1, nargs + 1))
    end
  end
end

--- Suspend the running coroutine until `thunk` calls back.
--- Must be called from inside a function started with `M.run`.
function M.await(thunk)
  return coroutine.yield(thunk)
end

--- Run `fn` as a coroutine, resuming it every time the thunk it yields
--- calls back. `on_done(...)` (optional) receives fn's final return values.
function M.run(fn, on_done)
  local co = coroutine.create(fn)

  local function step(...)
    local ok, thunk_or_result = coroutine.resume(co, ...)
    if not ok then
      error(thunk_or_result, 0)
    end
    if coroutine.status(co) == 'dead' then
      if on_done then
        on_done(thunk_or_result)
      end
      return
    end
    thunk_or_result(step)
  end

  step()
end

--- Wrap `fn` (a function that uses `M.await` internally) into a plain
--- callback-style function: `M.async(fn)(...)` runs fn to completion.
function M.async(fn)
  return function(...)
    local args = { ... }
    M.run(function()
      return fn(unpack(args))
    end)
  end
end

return M

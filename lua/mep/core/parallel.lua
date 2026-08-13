--- Real parallel processing via libuv's threadpool (`vim.uv.new_work`).
---
--- Unlike `core.job`, which is async-but-single-threaded (one Neovim event
--- loop interleaving I/O callbacks), this actually runs `work_fn` on worker
--- OS threads. That comes with a hard libuv constraint: `work_fn` is loaded
--- into an isolated Lua state, so it must be a self-contained function with
--- NO upvalues (no `vim.*`, no closed-over locals) and its arguments/return
--- values must be plain strings/numbers/booleans.
local uv = vim.uv or vim.loop

local M = {}

--- Run `work_fn(item)` for every item in `items` on the libuv threadpool.
--- `on_done(results)` is called once every item has completed, where
--- `results[i]` is a list of the return values of `work_fn(items[i])`.
---
---   parallel.map({ 1, 2, 3 }, function(n)
---     -- runs on a worker thread: no upvalues, no vim.* calls here
---     local sum = 0
---     for i = 1, n do sum = sum + i end
---     return sum
---   end, function(results)
---     vim.print(results) --> { {1}, {3}, {6} }
---   end)
function M.map(items, work_fn, on_done)
  local n = #items
  if n == 0 then
    if on_done then
      on_done({})
    end
    return
  end

  local results = {}
  local remaining = n

  for i, item in ipairs(items) do
    local work
    work = uv.new_work(work_fn, function(...)
      results[i] = { ... }
      remaining = remaining - 1
      if remaining == 0 and on_done then
        on_done(results)
      end
    end)
    work:queue(item)
  end
end

return M

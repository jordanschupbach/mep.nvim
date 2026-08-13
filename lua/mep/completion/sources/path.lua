--- Filesystem path completion: when the text right before the current
--- keyword prefix ends in `/` (so typing `/usr/lo` completes entries of
--- `/usr/` matching `lo`), offers that directory's own entries. Deliberately
--- keyed off the *same* keyword-shaped prefix `mep.completion.engine`
--- already computes for every source (rather than a separate
--- path-shaped prefix) — the item's `word` is just the matched entry's
--- own name (e.g. `local`, not `/usr/local`), consistent with the
--- engine's own `startcol` already pointing right after the `/`.
local M = {}

function M.complete(ctx, callback)
  local before = ctx.line:sub(1, ctx.col - #ctx.prefix)
  local dir_part = before:match('([~%w_%.%-/]*/)$')
  if not dir_part then
    callback({})
    return
  end

  local expanded = vim.fn.expand(dir_part)
  if expanded == '' or vim.fn.isdirectory(expanded) == 0 then
    callback({})
    return
  end

  local ok, entries = pcall(vim.fn.readdir, expanded)
  if not ok or not entries then
    callback({})
    return
  end

  local items = {}
  for _, name in ipairs(entries) do
    if ctx.prefix == '' or name:sub(1, #ctx.prefix) == ctx.prefix then
      local is_dir = vim.fn.isdirectory(expanded .. '/' .. name) == 1
      items[#items + 1] = { word = name, kind = is_dir and 'Folder' or 'File', menu = '[Path]' }
    end
  end
  callback(items)
end

return M

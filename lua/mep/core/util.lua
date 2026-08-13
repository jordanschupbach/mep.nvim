local uv = vim.uv or vim.loop

local M = {}

--- Debounce `fn`: repeated calls within `ms` milliseconds collapse into one,
--- delayed call carrying the arguments of the *last* invocation. `fn` runs
--- on the main loop via `vim.schedule`.
--- Returns `debounced_fn, timer` — call `timer:stop(); timer:close()` to
--- tear down the underlying uv timer when it's no longer needed.
function M.debounce(fn, ms)
  local timer = uv.new_timer()
  local function debounced(...)
    local args = { ... }
    local nargs = select('#', ...)
    timer:stop()
    timer:start(ms, 0, function()
      vim.schedule(function()
        fn(unpack(args, 1, nargs))
      end)
    end)
  end
  return debounced, timer
end

--- Walk upward from `path` (default: cwd) looking for any of `markers`
--- (default: `{ '.git' }`). Returns the containing directory, or `path`
--- itself if no marker is found.
function M.find_root(path, markers)
  path = path or vim.fn.getcwd()
  markers = markers or { '.git' }
  local found = vim.fs.find(markers, { path = path, upward = true })[1]
  if found then
    return vim.fs.dirname(found)
  end
  return path
end

--- Synchronous recursive file listing, used as a fallback when `rg`/`fd`
--- aren't on PATH. Skips dotfiles/dotdirs (matching `rg`'s default
--- behaviour of ignoring hidden entries and VCS directories). Appends
--- `{ filename = <relative path>, display = <relative path> }` entries
--- into `items` in place, capped at `max_items`.
function M.scan_dir(root, items, max_items)
  max_items = max_items or 20000

  local function walk(dir, rel)
    if #items >= max_items then
      return
    end
    local fd = uv.fs_scandir(dir)
    if not fd then
      return
    end
    while true do
      local name, typ = uv.fs_scandir_next(fd)
      if not name then
        break
      end
      if not vim.startswith(name, '.') then
        local full = dir .. '/' .. name
        local relpath = rel == '' and name or (rel .. '/' .. name)
        if typ == 'directory' then
          walk(full, relpath)
        elseif typ == 'file' then
          items[#items + 1] = { filename = relpath, display = relpath }
        end
        if #items >= max_items then
          return
        end
      end
    end
  end

  walk(root, '')
end

--- Open `filename` in the current window, optionally moving the cursor to
--- `lnum`/`col` (1-based). Shared by anything that jumps to a location on
--- disk — picker sources and mep.filetree both use this.
function M.open_file(filename, lnum, col)
  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, (col or 1) - 1 })
    vim.cmd('normal! zz')
  end
end

return M

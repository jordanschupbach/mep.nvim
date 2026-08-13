--- org-attach-style per-headline attachment directories: each headline
--- gets its own directory (derived from its `:ID:` property, via
--- mep.org.id) under a configured root, matching real org-attach's
--- default ID-based method. The ID is split 2/rest into two path
--- components (`ab/cdef.../`) — the same collision-avoidance hashing
--- trick real org-attach uses to keep any one directory from
--- accumulating thousands of entries, cheap to do since the ID is
--- already a random UUID.
local id_mod = require('mep.org.id')

local M = {}

--- The attachment directory for the headline containing `lnum` (creating
--- an `:ID:` property for it if it doesn't have one yet): `<base>/<root>/
--- <id[1:2]>/<id[3:]>/`, where `<base>` is `bufnr`'s own file directory
--- (falling back to the cwd for an unsaved buffer) and `root` defaults to
--- `"data"` (real org-attach's own default `org-attach-directory`).
--- `create` (default false) makes the directory on disk if it doesn't
--- exist yet. Returns the directory path, or nil if `lnum` isn't inside
--- a headline.
function M.dir_for(bufnr, lnum, root, create)
  local id = id_mod.get_or_create(bufnr, lnum)
  if not id then
    return nil
  end
  root = root or 'data'
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local base = bufname ~= '' and vim.fn.fnamemodify(bufname, ':h') or vim.fn.getcwd()
  local dir = base .. '/' .. root .. '/' .. id:sub(1, 2) .. '/' .. id:sub(3) .. '/'
  if create then
    vim.fn.mkdir(dir, 'p')
  end
  return dir
end

--- Copy `src_path` into the attachment directory for the headline
--- containing `lnum` (creating the directory and an `:ID:` property as
--- needed), keeping its basename. Returns the new path, or nil (with a
--- notification) on failure.
function M.attach(bufnr, lnum, src_path, root)
  local dir = M.dir_for(bufnr, lnum, root, true)
  if not dir then
    vim.notify('mep.org: cannot attach, no headline at cursor', vim.log.levels.WARN)
    return nil
  end
  if vim.fn.filereadable(src_path) == 0 then
    vim.notify('mep.org: attachment source not readable: ' .. src_path, vim.log.levels.WARN)
    return nil
  end
  local dest = dir .. vim.fn.fnamemodify(src_path, ':t')
  local uv = vim.uv or vim.loop
  local ok = uv.fs_copyfile(src_path, dest)
  if not ok then
    vim.notify('mep.org: failed to copy attachment to ' .. dest, vim.log.levels.WARN)
    return nil
  end
  return dest
end

--- Every attached file's basename for the headline containing `lnum`
--- (its `:ID:`-derived directory, if any and if it exists on disk), in
--- `vim.fn.readdir`'s own order.
function M.list(bufnr, lnum, root)
  local dir = M.dir_for(bufnr, lnum, root, false)
  if not dir or vim.fn.isdirectory(dir) == 0 then
    return {}
  end
  return vim.fn.readdir(dir)
end

--- Attach a file to the headline containing `lnum`, interactively:
--- prompts for a source path via `vim.ui.input` (completion `'file'`).
function M.attach_interactive(bufnr, lnum, root)
  vim.ui.input({ prompt = 'Attach file: ', completion = 'file' }, function(src_path)
    if not src_path or src_path == '' then
      return
    end
    local dest = M.attach(bufnr, lnum, vim.fn.expand(src_path), root)
    if dest then
      vim.notify('mep.org: attached to ' .. dest, vim.log.levels.INFO)
    end
  end)
end

return M

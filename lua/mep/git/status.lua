--- Project-wide git status for `mep.git`: `git status --porcelain=v1`,
--- parsed into staged/unstaged/untracked file lists, plus the small
--- set of whole-file mutations (`stage`/`unstage`/`discard`/`commit`)
--- the sidebar's action keymaps drive. All git access goes through
--- `mep.core.job` (see `spec/README.md` for why: a real subprocess
--- can't run inside the busted/nlua test harness, so any spec touching
--- this module mocks `vim.fn.jobstart` rather than actually shelling
--- out).
local core = require('mep.core')

local M = {}

local cache = { root = nil, staged = {}, unstaged = {}, untracked = {} }

--- One `--porcelain=v1` line -> `x, y, path` (the two status characters
--- and the affected path), or `nil` for a blank line. A rename/copy
--- line (`x` is `R`/`C`) is `"old -> new"` after the status columns;
--- only `new` is kept. A quoted path (git quotes anything containing
--- unusual characters) has its surrounding quotes stripped, not fully
--- unescaped — adequate for display/`git add`-by-path, not a complete
--- porcelain-quoting implementation.
local function parse_line(line)
  if #line < 4 then
    return nil
  end
  local x, y = line:sub(1, 1), line:sub(2, 2)
  local rest = line:sub(4)
  local path = rest
  if x == 'R' or x == 'C' then
    local _, new = rest:match('^(.-)%s%->%s(.+)$')
    path = new or rest
  end
  path = path:gsub('^"(.*)"$', '%1')
  return x, y, path
end

--- Async: re-run `git status` in `root`, updating the module-level
--- cache `M.get()` reads, then call `callback(status)` (status is that
--- same cache table). A path with changes in both the index and the
--- worktree (git's own "MM") appears in both `staged` and `unstaged`,
--- the same as `git status`'s own two-heading display for it. Leaves
--- the previous cache in place (still calling `callback`) if `git
--- status` itself fails.
function M.refresh(root, callback)
  local staged, unstaged, untracked = {}, {}, {}
  core.job.spawn({
    cmd = { 'git', 'status', '--porcelain=v1' },
    cwd = root,
    on_stdout = function(line)
      if line == '' then
        return
      end
      local x, y, path = parse_line(line)
      if not path then
        return
      end
      if x == '?' and y == '?' then
        untracked[#untracked + 1] = { path = path, code = x .. y }
        return
      end
      if x ~= ' ' and x ~= '!' then
        staged[#staged + 1] = { path = path, code = x .. y }
      end
      if y ~= ' ' and y ~= '!' then
        unstaged[#unstaged + 1] = { path = path, code = x .. y }
      end
    end,
    on_exit = function(code)
      if code == 0 then
        cache = { root = root, staged = staged, unstaged = unstaged, untracked = untracked }
      end
      if callback then
        callback(cache)
      end
    end,
  })
end

--- The last cache `M.refresh` populated (`{ root, staged, unstaged,
--- untracked }`, each a list of `{ path, code }`) — empty lists before
--- the first `refresh`.
function M.get()
  return cache
end

--- `git add -- path` (stage the whole file), cwd `root`. `callback(ok)`.
function M.stage(root, path, callback)
  core.job.spawn({
    cmd = { 'git', 'add', '--', path },
    cwd = root,
    on_exit = function(code)
      if callback then
        callback(code == 0)
      end
    end,
  })
end

--- `git reset -- path` (unstage, worktree changes untouched), cwd
--- `root`. `callback(ok)`.
function M.unstage(root, path, callback)
  core.job.spawn({
    cmd = { 'git', 'reset', '--', path },
    cwd = root,
    on_exit = function(code)
      if callback then
        callback(code == 0)
      end
    end,
  })
end

--- Discard local changes to `path`: an untracked file is deleted from
--- disk directly (nothing for git to check out back to); a tracked one
--- is restored via `git checkout -- path`, cwd `root`. `callback(ok)`.
function M.discard(root, path, is_untracked, callback)
  if is_untracked then
    local ok = vim.fn.delete(root .. '/' .. path) == 0
    if callback then
      callback(ok)
    end
    return
  end
  core.job.spawn({
    cmd = { 'git', 'checkout', '--', path },
    cwd = root,
    on_exit = function(code)
      if callback then
        callback(code == 0)
      end
    end,
  })
end

--- `git commit -m message`, cwd `root`. `callback(ok)`.
function M.commit(root, message, callback)
  core.job.spawn({
    cmd = { 'git', 'commit', '-m', message },
    cwd = root,
    on_exit = function(code)
      if callback then
        callback(code == 0)
      end
    end,
  })
end

--- Test/dev-only: drop the cache back to empty.
function M._reset()
  cache = { root = nil, staged = {}, unstaged = {}, untracked = {} }
end

return M

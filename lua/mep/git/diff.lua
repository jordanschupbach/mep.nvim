--- Hunk math for `mep.git`: fetching a file's indexed (staged) blob
--- content and diffing it against a buffer's current content. Diffing
--- itself (`compute_hunks`) is pure — built on Neovim's own built-in
--- `vim.diff(a, b, { result_type = 'indices' })`, not a shelled-out
--- `git diff`, so it's fully unit-testable without mocking a
--- subprocess. Only `get_indexed_content` (fetching the blob to diff
--- against) touches git itself, via `mep.core.job`.
local core = require('mep.core')

local M = {}

--- Async: the currently-indexed (staged) content of `relpath` (relative
--- to `root`, the repo root `git show` is run from) — `callback(text)`,
--- or `callback(nil)` for an untracked file / anything `git show`
--- can't resolve. `text` has no trailing newline; pass it straight to
--- `M.split_lines`.
function M.get_indexed_content(root, relpath, callback)
  local out = {}
  core.job.spawn({
    cmd = { 'git', 'show', ':' .. relpath },
    cwd = root,
    on_stdout = function(line)
      out[#out + 1] = line
    end,
    on_exit = function(code)
      if code == 0 then
        callback(table.concat(out, '\n'))
      else
        callback(nil)
      end
    end,
  })
end

--- `text` (no trailing newline expected either way) split into a list
--- of lines — `''` becomes `{}`, not `{ '' }`, so an untracked file's
--- `nil`-turned-`''` "indexed content" diffs as zero old lines rather
--- than one blank one.
function M.split_lines(text)
  if text == nil or text == '' then
    return {}
  end
  return vim.split(text, '\n', { plain = true })
end

--- Hunks between old text `a` (`nil`/`''` for an untracked file — diffs
--- as "every line added") and new text `b`, both `\n`-joined (no
--- trailing newline needed). Each hunk is `{ kind = 'add'|'delete'|
--- 'change', start_a, count_a, start_b, count_b }` — the same
--- `@@ -start_a,count_a +start_b,count_b @@` unified-diff convention
--- `vim.diff`'s own `indices` result already follows (1-based; a `0`
--- start means "before line 1", e.g. an insertion/deletion at the very
--- top of the file).
function M.compute_hunks(a, b)
  a = a or ''
  b = b or ''
  local ok, indices = pcall(vim.diff, a, b, { result_type = 'indices', ctxlen = 0 })
  if not ok or not indices then
    return {}
  end
  local hunks = {}
  for _, idx in ipairs(indices) do
    local start_a, count_a, start_b, count_b = idx[1], idx[2], idx[3], idx[4]
    local kind = count_a == 0 and 'add' or (count_b == 0 and 'delete' or 'change')
    hunks[#hunks + 1] = { kind = kind, start_a = start_a, count_a = count_a, start_b = start_b, count_b = count_b }
  end
  return hunks
end

--- The buffer-side (1-based) rows `hunk` should carry a sign on, each
--- `{ row, kind }` (`kind` one of `add`/`change`/`delete`/`topdelete`/
--- `changedelete` — `mep.git.config.defaults.signs`' own keys). A pure
--- `add`/`delete` hunk signs every added row (or, for a delete, the
--- single row deletion happened at — `topdelete` if that's the very
--- top of the file, `delete` otherwise); a `change` hunk signs every
--- overlapping row `change`, any extra *added* rows beyond that overlap
--- `add`, and — if there are extra *removed* rows instead (the file
--- got shorter here) — re-marks the last changed row `changedelete`.
function M.sign_rows(hunk)
  if hunk.kind == 'add' then
    local rows = {}
    for i = 0, hunk.count_b - 1 do
      rows[#rows + 1] = { row = hunk.start_b + i, kind = 'add' }
    end
    return rows
  end

  if hunk.kind == 'delete' then
    local row = hunk.start_b == 0 and 1 or hunk.start_b
    return { { row = row, kind = hunk.start_b == 0 and 'topdelete' or 'delete' } }
  end

  local rows = {}
  local overlap = math.min(hunk.count_a, hunk.count_b)
  for i = 0, overlap - 1 do
    rows[#rows + 1] = { row = hunk.start_b + i, kind = 'change' }
  end
  if hunk.count_b > overlap then
    for i = overlap, hunk.count_b - 1 do
      rows[#rows + 1] = { row = hunk.start_b + i, kind = 'add' }
    end
  elseif hunk.count_a > overlap then
    rows[#rows].kind = 'changedelete'
  end
  return rows
end

--- A minimal, zero-context unified-diff patch for just `hunk`, suitable
--- for `git apply --cached --unidiff-zero -` (`mep.git.gutter.
--- stage_hunk`'s own use) — `indexed_lines`/`buffer_lines` are `M.
--- split_lines` output for the old/new content `hunk` came from.
function M.build_patch(relpath, indexed_lines, buffer_lines, hunk)
  local lines = {
    'diff --git a/' .. relpath .. ' b/' .. relpath,
    '--- a/' .. relpath,
    '+++ b/' .. relpath,
    string.format('@@ -%d,%d +%d,%d @@', hunk.start_a, hunk.count_a, hunk.start_b, hunk.count_b),
  }
  for i = 0, hunk.count_a - 1 do
    lines[#lines + 1] = '-' .. (indexed_lines[hunk.start_a + i] or '')
  end
  for i = 0, hunk.count_b - 1 do
    lines[#lines + 1] = '+' .. (buffer_lines[hunk.start_b + i] or '')
  end
  return table.concat(lines, '\n') .. '\n'
end

return M

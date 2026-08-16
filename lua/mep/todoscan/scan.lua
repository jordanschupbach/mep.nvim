--- Project-wide TODO/FIXME/HACK/NOTE-style comment scanning: `rg` when
--- available (respects .gitignore, skips .git — the same optional-
--- external-tool posture `mep.picker.find_files`/`live_grep` take
--- toward it), falling back to a synchronous walk+grep via
--- `core.util.scan_dir` otherwise.
local core = require('mep.core')

local M = {}

--- Whether `line` contains one of `keywords` as a whole word (Lua's
--- `%f[%w]`/`%f[%W]` frontier patterns — the same keyword-boundary idea
--- `mep.completion.engine`'s own prefix detection uses `[%w_]` for,
--- adapted to bound both sides of a match rather than just trailing).
--- Keywords are tried in the order given, first match wins. Returns the
--- matched keyword plus its 0-indexed `[start, end)` column span (the
--- shape `nvim_buf_set_extmark`'s own `col`/`end_col` expect), or
--- nothing if none matched.
function M.match_line(line, keywords)
  for _, kw in ipairs(keywords) do
    local pattern = '%f[%w]' .. vim.pesc(kw) .. '%f[%W]'
    local s, e = line:find(pattern)
    if s then
      return kw, s - 1, e
    end
  end
  return nil
end

--- Escape a keyword for use inside an `rg` (Rust regex) alternation —
--- different metacharacters than Lua's own pattern escaping
--- (`vim.pesc`), which is why this scanner needs its own.
local function escape_regex(s)
  return (s:gsub('([%.%^%$%*%+%?%(%)%[%]{}|\\])', '\\%1'))
end

local function scan_with_rg(cwd, keywords, callback)
  local escaped = {}
  for i, kw in ipairs(keywords) do
    escaped[i] = escape_regex(kw)
  end
  local pattern = '\\b(' .. table.concat(escaped, '|') .. ')\\b'
  local items = {}
  core.job.spawn({
    -- The trailing '.' is required: without an explicit path, `rg`
    -- falls back to reading stdin when stdin isn't a tty (as under
    -- jobstart), which would hang forever since nothing ever closes
    -- that pipe — same reasoning mep.picker.sources.grep's own header
    -- comment gives.
    cmd = { 'rg', '--vimgrep', '--no-heading', '--color=never', '-e', pattern, '.' },
    cwd = cwd,
    on_stdout = function(line)
      local file, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')
      if file then
        local keyword = M.match_line(text, keywords)
        if keyword then
          items[#items + 1] = {
            filename = file,
            lnum = tonumber(lnum),
            col = tonumber(col),
            keyword = keyword,
            text = vim.trim(text),
          }
        end
      end
    end,
    on_exit = function()
      callback(items)
    end,
  })
end

local function scan_pure_lua(cwd, keywords, callback)
  local files = {}
  core.util.scan_dir(cwd, files)
  local items = {}
  for _, f in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, cwd .. '/' .. f.filename)
    if ok then
      for lnum, line in ipairs(lines) do
        local keyword, col_start = M.match_line(line, keywords)
        if keyword then
          items[#items + 1] = {
            filename = f.filename,
            lnum = lnum,
            col = col_start + 1,
            keyword = keyword,
            text = vim.trim(line),
          }
        end
      end
    end
  end
  callback(items)
end

--- Scan every project file under `cwd` (default: `core.util.find_root()`)
--- for `keywords`, calling `callback(items)` once with every match —
--- each item `{ filename (relative to cwd), lnum, col (both 1-based),
--- keyword, text }`. Synchronous (calls back immediately) in the
--- pure-Lua fallback, asynchronous via `rg` otherwise — callers that
--- stream partial results into a picker (`mep.todoscan.picker`'s own
--- `on_open`) work the same way either way.
function M.scan(cwd, keywords, callback)
  cwd = cwd or core.util.find_root()
  if vim.fn.executable('rg') == 1 then
    scan_with_rg(cwd, keywords, callback)
  else
    scan_pure_lua(cwd, keywords, callback)
  end
end

return M

--- Local problem file discovery/parsing: one `.org` file per problem
--- under `config.options.problems_dir`, its file-level `#+TITLE:`/
--- `#+PROPERTY: LEETCODE_SLUG ...`/`#+PROPERTY: LEETCODE_DIFFICULTY
--- ...` keywords (real org-mode's own file-keyword syntax — not
--- `mep.org.property`'s headline-drawer properties, a different, file-
--- scoped thing) for metadata, and its src blocks (`mep.org.babel.
--- find_blocks`) for the solution/tests: the first block is the
--- solution, every block after it is a separate test case.
local babel = require('mep.org.babel')

local M = {}

--- Load `path` into a buffer without displaying it, reusing an
--- already-open buffer's live content if there is one — the same idiom
--- `mep.org.agenda`'s own (private) `load_buf` helper uses.
local function load_buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end
M.load_buf = load_buf

--- `bufnr`'s own `#+TITLE:`/`#+PROPERTY: LEETCODE_SLUG ...`/
--- `#+PROPERTY: LEETCODE_DIFFICULTY ...` file keywords (checked over
--- just the first 30 lines — real org file keywords always sit at the
--- very top, before any headline): `{ title, slug, difficulty }`, any
--- of which may be nil if that keyword isn't present.
function M.metadata(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(30, vim.api.nvim_buf_line_count(bufnr)), false)
  local meta = {}
  for _, line in ipairs(lines) do
    local title = line:match('^#%+TITLE:%s*(.-)%s*$')
    if title then
      meta.title = title
    end
    local key, value = line:match('^#%+PROPERTY:%s*(%S+)%s+(.-)%s*$')
    if key then
      if key:upper() == 'LEETCODE_SLUG' then
        meta.slug = value
      elseif key:upper() == 'LEETCODE_DIFFICULTY' then
        meta.difficulty = value
      elseif key:upper() == 'LEETCODE_QUESTION_ID' then
        meta.question_id = value
      end
    end
  end
  return meta
end

--- Every `.org` file directly inside `problems_dir`: `{ path, title,
--- slug, difficulty }` (`title` falls back to the bare filename when
--- there's no `#+TITLE:`), sorted by title.
function M.list(problems_dir)
  local paths = vim.fn.glob(problems_dir .. '/*.org', false, true)
  local out = {}
  for _, path in ipairs(paths) do
    local meta = M.metadata(load_buf(path))
    out[#out + 1] = {
      path = path,
      title = meta.title or vim.fn.fnamemodify(path, ':t:r'),
      slug = meta.slug,
      difficulty = meta.difficulty,
    }
  end
  table.sort(out, function(a, b)
    return a.title < b.title
  end)
  return out
end

--- `bufnr`'s solution block (the first src block in the file) and its
--- test blocks (every one after it), both `mep.org.babel.find_blocks`'s
--- own shape. `solution` is nil (with `tests = {}`) for a file with no
--- src blocks at all.
function M.blocks(bufnr)
  local blocks = babel.find_blocks(bufnr)
  if #blocks == 0 then
    return nil, {}
  end
  local tests = {}
  for i = 2, #blocks do
    tests[#tests + 1] = blocks[i]
  end
  return blocks[1], tests
end

return M

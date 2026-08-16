--- Recognizes a YAML (`---`)/TOML (`+++`) front-matter block at the
--- very top of a markdown buffer (real static-site-generator
--- convention — Jekyll/Hugo/Zola/etc. all use exactly this shape) and
--- shades its background so it reads as a distinct block, the same
--- overlay-extmark technique `mep.markdown.codeblocks` uses for fenced
--- code. Mirrors that module's own attach/detach, debounced-recompute-
--- on-text-change lifecycle.
local core = require('mep.core')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_markdown_frontmatter')
local state = {} -- bufnr -> { debounced, timer, augroup }

--- The front-matter block's own line range in `bufnr` — `1, end_lnum`
--- (1-indexed, inclusive of both delimiter lines) if line 1 is exactly
--- `---`/`+++` and a matching closing delimiter line exists somewhere
--- below it; nil otherwise (no front matter, or an unterminated opening
--- delimiter — deliberately not highlighted as "open to end of buffer"
--- the way `mep.markdown.codeblocks` treats an unclosed fence, since an
--- unterminated `---`/`+++` on line 1 is far more likely to just be a
--- literal thematic break/heading underline than a front-matter block
--- someone forgot to close).
local function frontmatter_region(bufnr)
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if first ~= '---' and first ~= '+++' then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 1, -1, false)
  for i, line in ipairs(lines) do
    if line == first then
      return 1, i + 1
    end
  end
  return nil
end
M.region = frontmatter_region

local function clear_highlight(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function place_highlight(bufnr)
  clear_highlight(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local start_lnum, end_lnum = frontmatter_region(bufnr)
  if not start_lnum then
    return
  end
  for row = start_lnum, end_lnum do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row - 1, 0, {
      end_row = row,
      hl_group = 'MepMarkdownFrontmatter',
      hl_eol = true,
      priority = 100,
    })
  end
end

--- Start tracking `bufnr`: shade now, and keep it up to date (debounced)
--- as the buffer changes. Safe to call more than once — already-
--- attached is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] then
    return
  end

  local debounced, timer = core.util.debounce(function()
    place_highlight(bufnr)
  end, 100)

  local grp = vim.api.nvim_create_augroup('MepMarkdownFrontmatter' .. bufnr, { clear = true })
  state[bufnr] = { debounced = debounced, timer = timer, augroup = grp }

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
    group = grp,
    buffer = bufnr,
    callback = debounced,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = grp,
    buffer = bufnr,
    once = true,
    callback = function()
      M.detach(bufnr)
    end,
  })

  place_highlight(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- highlight. Safe to call on a buffer that was never attached.
function M.detach(bufnr)
  local st = state[bufnr]
  if not st then
    return
  end
  if st.timer then
    pcall(function()
      st.timer:stop()
      st.timer:close()
    end)
  end
  if st.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, st.augroup)
  end
  clear_highlight(bufnr)
  state[bufnr] = nil
end

function M.is_attached(bufnr)
  return state[bufnr] ~= nil
end

--- Test/dev-only: detach every currently-tracked buffer.
function M._reset()
  local attached = {}
  for bufnr in pairs(state) do
    attached[#attached + 1] = bufnr
  end
  for _, bufnr in ipairs(attached) do
    M.detach(bufnr)
  end
end

return M

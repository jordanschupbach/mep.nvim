--- Per-buffer background highlight for fenced code blocks (``` or ~~~
--- fences, inclusive of both fence lines) — a full-width `hl_eol`
--- extmark per line so a code block reads as a distinct shaded band
--- instead of blending into surrounding prose. Line-pattern matching,
--- not treesitter (same "works standalone" reasoning as mep.markdown.
--- gutter's own heading-level detection). Mirrors mep.git.gutter's own
--- attach/detach, debounced-recompute-on-text-change lifecycle.
local core = require('mep.core')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_markdown_codeblocks')
local state = {} -- bufnr -> { debounced, timer, augroup }

local function is_fence(line)
  return line:match('^%s*```') ~= nil or line:match('^%s*~~~') ~= nil
end

local function clear_highlights(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function shade(bufnr, from_line, to_line)
  for row = from_line, to_line do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row - 1, 0, {
      end_row = row,
      hl_group = 'MepMarkdownCodeBlock',
      hl_eol = true,
      priority = 100,
    })
  end
end

--- A fence still open at end-of-buffer is shaded through to the last
--- line too (rather than left unshaded until it's closed) — nicer live
--- feedback while typing a block, and matches what it'll look like the
--- moment the closing fence is added.
local function place_highlights(bufnr)
  clear_highlights(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local open_at = nil
  for i, line in ipairs(lines) do
    if open_at then
      if is_fence(line) then
        shade(bufnr, open_at, i)
        open_at = nil
      end
    elseif is_fence(line) then
      open_at = i
    end
  end
  if open_at then
    shade(bufnr, open_at, #lines)
  end
end

--- Start tracking `bufnr`: shade now, and keep it up to date
--- (debounced) as the buffer changes. Safe to call more than once —
--- already-attached is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] then
    return
  end

  local debounced, timer = core.util.debounce(function()
    place_highlights(bufnr)
  end, 100)

  local grp = vim.api.nvim_create_augroup('MepMarkdownCodeBlocks' .. bufnr, { clear = true })
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

  place_highlights(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- highlights. Safe to call on a buffer that was never attached.
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
  clear_highlights(bufnr)
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

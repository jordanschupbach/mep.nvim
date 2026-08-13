--- Per-buffer sign-column markers for markdown headers: one sign per
--- ATX heading line (`#` .. `######`), showing its level (`config.
--- options.gutter_symbols`) in the same color as that level's own
--- heading highlight (`mep.markdown.highlights`'s own `@markup.
--- heading.N` groups). Line-pattern matching, not treesitter — same
--- "works standalone, no parser required" reasoning as `mep.org.
--- headline`'s own pure-Lua headline parsing. Mirrors `mep.git.
--- gutter`'s own attach/detach, debounced-recompute-on-text-change
--- lifecycle.
local core = require('mep.core')
local config = require('mep.markdown.config')

local M = {}

local sign_ns = vim.api.nvim_create_namespace('mep_markdown_gutter')
local state = {} -- bufnr -> { debounced, timer, augroup }

--- The heading level (1-6) of `line`, or nil if it isn't an ATX
--- heading (`#note` and 7+ leading `#`s are deliberately not headings,
--- matching CommonMark).
local function level_of(line)
  local hashes = line:match('^(#+)%s')
  if not hashes or #hashes > 6 then
    return nil
  end
  return #hashes
end

local function clear_signs(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, sign_ns, 0, -1)
  end
end

local function place_signs(bufnr)
  clear_signs(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local level = level_of(line)
    local text = level and config.options.gutter_symbols[level]
    if text then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, sign_ns, i - 1, 0, {
        sign_text = text,
        sign_hl_group = '@markup.heading.' .. level,
      })
    end
  end
end

--- Start tracking `bufnr`: place signs now, and keep them up to date
--- (debounced) as the buffer changes. Safe to call more than once —
--- already-attached is a no-op.
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if state[bufnr] then
    return
  end

  local debounced, timer = core.util.debounce(function()
    place_signs(bufnr)
  end, 100)

  local grp = vim.api.nvim_create_augroup('MepMarkdownGutter' .. bufnr, { clear = true })
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

  place_signs(bufnr)
end

--- Stop tracking `bufnr`: tear down its timer/autocmds and clear its
--- signs. Safe to call on a buffer that was never attached.
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
  clear_signs(bufnr)
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

--- Window/buffer management and icon-aware rendering for mep.filetree. A
--- real vertical split (not a floating window, unlike mep.picker) since a
--- file tree is a persistent side panel that should participate in normal
--- window layout.
local icons = require('mep.icons')

local M = {}

local icon_ns = vim.api.nvim_create_namespace('mep_filetree_icons')
local name_ns = vim.api.nvim_create_namespace('mep_filetree_names')
local hint_ns = vim.api.nvim_create_namespace('mep_filetree_hint')

--- Open a left-hand vertical split of `width` columns with a fresh
--- scratch buffer. Returns `buf, win`.
function M.create_window(width)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mep-filetree'

  vim.cmd('topleft ' .. tostring(width) .. 'vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  -- Otherwise fair game for Neovim's 'equalalways' (on by default):
  -- opening/closing *any* other window in the tabpage would silently
  -- resize this persistent panel too — confirmed the hard way, exactly
  -- what made unrelated splits visibly resize the file tree.
  vim.wo[win].winfixwidth = true

  return buf, win
end

function M.close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

-- `node.is_gitignored`/`node.is_dotfile` (mep.filetree.tree's own scan)
-- -> a trailing " [i]"/" [.]" suffix plus the name highlight group that
-- covers both the name and that suffix. Gitignored wins over dotfile for
-- an entry that's somehow both (git doesn't care whether a path starts
-- with '.') — it's the rarer, more specific reason something's only
-- visible because show_hidden/show_gitignored got toggled on, and the
-- more useful one to call out: a dotfile's own name already reveals it's
-- a dotfile, but nothing about a gitignored entry's *name* reveals that
-- on its own (a `build/` or `node_modules/` doesn't look any different
-- from a real one). Falls back to `MepFiletreeDirectory` for an ordinary
-- (not hidden-shown) directory, same as before this existed; a plain
-- file gets neither, same as before too.
local function hidden_marker(node)
  if node.is_gitignored then
    return ' [i]', 'MepFiletreeGitignored'
  end
  if node.is_dotfile then
    return ' [.]', 'MepFiletreeDotfile'
  end
  return '', node.is_dir and 'MepFiletreeDirectory' or nil
end

-- Builds one line's text plus the byte ranges to highlight, tracking byte
-- offsets by hand (rather than string.format) since the glyphs involved
-- are multi-byte UTF-8 and nvim_buf_add_highlight takes byte columns.
local function render_node(node)
  local indent = string.rep('  ', node.depth)
  local marker = node.is_dir and (icons.get_expand_marker(node.expanded) .. ' ') or '  '
  local icon, icon_hl
  if node.is_dir then
    icon, icon_hl = icons.get_directory_icon(node.expanded)
  else
    icon, icon_hl = icons.get_file_icon(node.name)
  end

  local prefix = indent .. marker
  local icon_start = #prefix
  local icon_end = icon_start + #icon

  local name = node.name .. (node.is_dir and '/' or '')
  local name_start = icon_end + 1 -- one space between icon and name
  local name_end = name_start + #name

  local suffix, name_hl = hidden_marker(node)
  local name_hl_end = name_end + #suffix

  local line = prefix .. icon .. ' ' .. name .. suffix
  return line, icon_start, icon_end, icon_hl, name_start, name_hl_end, name_hl
end

--- Render `nodes` (as returned by tree.flatten) into `buf`, one per line,
--- with icon and name highlights applied (directories get
--- `MepFiletreeDirectory`; an entry only visible because show_hidden/
--- show_gitignored is on gets a dim `[.]`/`[i]` suffix instead — see
--- `hidden_marker`). When `win`
--- is given, a footer is pinned to the *bottom of the window* — a
--- horizontal rule (sized to the window's current width) and a "Press ?
--- for help" hint, both dimmed via `MepFiletreeHint` — by padding with
--- blank lines when the tree is shorter than the window, rather than
--- just appending it right after the last node (which would otherwise
--- leave it floating directly under a short tree instead of anchored to
--- the panel's own bottom edge). `win` is optional — omit it (as e.g.
--- tests that don't need a real window do) to render just the tree
--- lines, no footer.
function M.render(buf, nodes, win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local marks = {}
  for i, node in ipairs(nodes) do
    local line, icon_start, icon_end, icon_hl, name_start, name_hl_end, name_hl = render_node(node)
    lines[i] = line
    marks[i] = { icon_start, icon_end, icon_hl, name_start, name_hl_end, name_hl }
  end

  local footer_start = nil
  if win and vim.api.nvim_win_is_valid(win) then
    local footer = { string.rep('─', vim.api.nvim_win_get_width(win)), 'Press ? for help' }
    local pad = vim.api.nvim_win_get_height(win) - #lines - #footer
    for _ = 1, pad do
      lines[#lines + 1] = ''
    end
    footer_start = #lines + 1
    for _, l in ipairs(footer) do
      lines[#lines + 1] = l
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, icon_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, name_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
  for i, m in ipairs(marks) do
    local icon_start, icon_end, icon_hl, name_start, name_hl_end, name_hl = m[1], m[2], m[3], m[4], m[5], m[6]
    pcall(vim.api.nvim_buf_add_highlight, buf, icon_ns, icon_hl, i - 1, icon_start, icon_end)
    if name_hl then
      pcall(vim.api.nvim_buf_add_highlight, buf, name_ns, name_hl, i - 1, name_start, name_hl_end)
    end
  end
  if footer_start then
    for i = footer_start, #lines do
      pcall(vim.api.nvim_buf_add_highlight, buf, hint_ns, 'MepFiletreeHint', i - 1, 0, -1)
    end
  end
  vim.bo[buf].modifiable = false
end

return M

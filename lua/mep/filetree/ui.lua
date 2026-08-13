--- Window/buffer management and icon-aware rendering for mep.filetree. A
--- real vertical split (not a floating window, unlike mep.picker) since a
--- file tree is a persistent side panel that should participate in normal
--- window layout.
local icons = require('mep.icons')

local M = {}

local icon_ns = vim.api.nvim_create_namespace('mep_filetree_icons')
local name_ns = vim.api.nvim_create_namespace('mep_filetree_names')

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

  local line = prefix .. icon .. ' ' .. name
  return line, icon_start, icon_end, icon_hl, name_start, name_end
end

--- Render `nodes` (as returned by tree.flatten) into `buf`, one per line,
--- with icon and (for directories) name highlights applied.
function M.render(buf, nodes)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local marks = {}
  for i, node in ipairs(nodes) do
    local line, icon_start, icon_end, icon_hl, name_start, name_end = render_node(node)
    lines[i] = line
    marks[i] = { icon_start, icon_end, icon_hl, node.is_dir, name_start, name_end }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, icon_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, name_ns, 0, -1)
  for i, m in ipairs(marks) do
    local icon_start, icon_end, icon_hl, is_dir, name_start, name_end = m[1], m[2], m[3], m[4], m[5], m[6]
    pcall(vim.api.nvim_buf_add_highlight, buf, icon_ns, icon_hl, i - 1, icon_start, icon_end)
    if is_dir then
      pcall(vim.api.nvim_buf_add_highlight, buf, name_ns, 'MepFiletreeDirectory', i - 1, name_start, name_end)
    end
  end
  vim.bo[buf].modifiable = false
end

return M

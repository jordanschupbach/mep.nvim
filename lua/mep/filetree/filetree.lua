--- Aggregator and controller for mep's file tree library: a single
--- persistent tree panel (unlike mep.picker, there's only ever one at a
--- time). Wires the pure tree data structure (tree.lua) to the
--- window/rendering layer (ui.lua), styled via mep.icons.
local core = require('mep.core')
local config = require('mep.filetree.config')
local tree = require('mep.filetree.tree')
local ui = require('mep.filetree.ui')

local M = {}

local state = {
  root_node = nil,
  win = nil,
  buf = nil,
  nodes = {},
  target_win = nil,
  augroup = nil,
}

--- Configure the filetree library. See mep.filetree.config.defaults for
--- width/root/show_hidden/keymaps. Works with sensible defaults even if
--- this is never called.
function M.setup(opts)
  return config.setup(opts)
end

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end
M.is_open = is_open

local function render()
  tree.ensure_expanded_loaded(state.root_node, config.options.show_hidden)
  state.nodes = tree.flatten(state.root_node)
  ui.render(state.buf, state.nodes)
end

local function node_at_cursor()
  if not is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.nodes[lnum]
end

local function set_cursor_to_node(node)
  if not node or not is_open() then
    return
  end
  for i, n in ipairs(state.nodes) do
    if n == node then
      pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
      return
    end
  end
end

local function open_node()
  local node = node_at_cursor()
  if not node then
    return
  end
  if node.is_dir then
    tree.toggle_expand(node, config.options.show_hidden)
    render()
  else
    if state.target_win and vim.api.nvim_win_is_valid(state.target_win) then
      vim.api.nvim_set_current_win(state.target_win)
    end
    core.util.open_file(node.path)
  end
end

local function expand_node()
  local node = node_at_cursor()
  if not node or not node.is_dir then
    return
  end
  if not node.expanded then
    tree.toggle_expand(node, config.options.show_hidden)
    render()
  end
end

local function collapse_node()
  local node = node_at_cursor()
  if not node then
    return
  end
  if node.is_dir and node.expanded then
    tree.toggle_expand(node, config.options.show_hidden)
    render()
  elseif node.parent then
    set_cursor_to_node(node.parent)
  end
end

--- Re-scan every currently-expanded directory (collapsed ones stay lazily
--- unloaded) and re-render. Expand/collapse state is preserved.
function M.refresh()
  if not state.root_node then
    return
  end
  tree.invalidate(state.root_node)
  if is_open() then
    render()
  end
end

local function bind_keymaps()
  local map_opts = { buffer = state.buf, silent = true, nowait = true }
  local function map_all(lhs_list, fn, desc)
    local opts = desc and vim.tbl_extend('force', map_opts, { desc = desc }) or map_opts
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set('n', lhs, fn, opts)
    end
  end
  local keymaps = config.options.keymaps
  map_all(keymaps.open, open_node, 'Open file / toggle directory')
  map_all(keymaps.expand, expand_node, 'Expand directory')
  map_all(keymaps.collapse, collapse_node, 'Collapse directory / go to parent')
  map_all(keymaps.close, M.close, 'Close the file tree')
  map_all(keymaps.refresh, M.refresh, 'Refresh the file tree')
end

local function bind_autocmds()
  state.augroup = vim.api.nvim_create_augroup('MepFiletree', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = state.augroup,
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
    end,
  })
end

--- Open the tree (no-op if already open). `opts.root` overrides
--- `mep.filetree.config.options.root`, which itself falls back to
--- `core.util.find_root()`. Reuses the previous root node (preserving
--- expand state) unless the resolved root path has changed.
function M.open(opts)
  opts = opts or {}
  if is_open() then
    return
  end

  local root_path = opts.root or config.options.root or core.util.find_root()
  if not state.root_node or state.root_node.path ~= root_path then
    state.root_node = tree.new_root(root_path)
  end

  state.target_win = vim.api.nvim_get_current_win()
  state.buf, state.win = ui.create_window(config.options.width)

  bind_keymaps()
  bind_autocmds()

  render()
end

--- Close the tree window (no-op if not open). Root node / expand state is
--- kept for next time — see `reset()` to discard it too.
function M.close()
  if not is_open() then
    return
  end
  ui.close_window(state.win)
  state.win = nil
  state.buf = nil
end

function M.toggle(opts)
  if is_open() then
    M.close()
  else
    M.open(opts)
  end
end

--- Close the tree (if open) and forget the cached root node/expand
--- state, so the next open() rebuilds from scratch (e.g. after `:cd`ing
--- to a different project).
function M.reset()
  M.close()
  state.root_node = nil
  state.nodes = {}
end

return M

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
  ui.render(state.buf, state.nodes, state.win)
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

--- Find a node by its on-disk path among the currently rendered
--- (visible) nodes — used after a mutating op (add/rename) re-renders the
--- tree to relocate the cursor onto the node it just created/renamed.
--- Only ever finds it if the containing directory is expanded, same as
--- anything else that's actually on screen.
local function find_node_by_path(path)
  for _, n in ipairs(state.nodes) do
    if n.path == path then
      return n
    end
  end
  return nil
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

--- Re-scan just `node` (a directory) in place and re-render, unlike
--- `M.refresh()` (bound to `R`), which invalidates the *whole* tree from
--- the root down. `tree.invalidate` discards a directory's `.children`
--- array outright — any node beneath it that a caller mutated (e.g. an
--- `expanded` flag flipped just before calling this) would otherwise be
--- silently replaced by a fresh, default-collapsed object on the next
--- scan, and any expanded directory elsewhere in the tree would collapse
--- along with it. Scoping the invalidation to just the directory whose
--- listing actually changed avoids both: `node` itself keeps its
--- identity (it's still reachable through its own parent's unchanged
--- `.children`), and every sibling subtree is left completely alone.
local function invalidate_and_render(node)
  tree.invalidate(node)
  if is_open() then
    render()
  end
end

--- Create a new file or directory. Prompts for a name relative to the
--- node under the cursor (inside it, if the node is a directory; as a
--- sibling, if it's a file) — a trailing `/` on the entered name creates
--- a directory instead of a file. Errors (already exists, mkdir/write
--- failure) are reported via vim.notify rather than raised, same as
--- every other filetree action.
local function add_node()
  local node = node_at_cursor()
  local container = state.root_node
  if node then
    container = node.is_dir and node or node.parent
  end
  if not container then
    return
  end

  vim.ui.input({ prompt = 'New file/directory (end with / for a directory): ' }, function(name)
    if not name or name == '' then
      return
    end
    local is_dir = vim.endswith(name, '/')
    local clean_name = is_dir and name:sub(1, -2) or name
    if clean_name == '' then
      return
    end
    local path = container.path .. '/' .. clean_name

    if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
      vim.notify('mep.filetree: ' .. path .. ' already exists', vim.log.levels.ERROR)
      return
    end

    local ok
    if is_dir then
      ok = vim.fn.mkdir(path, 'p') == 1
    else
      vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
      ok = vim.fn.writefile({}, path) == 0
    end
    if not ok then
      vim.notify('mep.filetree: failed to create ' .. path, vim.log.levels.ERROR)
      return
    end

    -- Show the new entry even if it landed inside a directory that was
    -- collapsed (a no-op when `container` was already expanded, e.g. the
    -- sibling-of-a-file case).
    container.expanded = true
    invalidate_and_render(container)
    set_cursor_to_node(find_node_by_path(path))
  end)
end

--- Rename the node under the cursor (prompts with its current name
--- pre-filled). Refuses to rename the tree root, and refuses to
--- overwrite an existing file/directory at the destination.
local function rename_node()
  local node = node_at_cursor()
  if not node then
    return
  end
  if not node.parent then
    vim.notify('mep.filetree: cannot rename the tree root', vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = 'Rename: ', default = node.name }, function(new_name)
    if not new_name or new_name == '' or new_name == node.name then
      return
    end
    local new_path = vim.fn.fnamemodify(node.path, ':h') .. '/' .. new_name

    if vim.fn.isdirectory(new_path) == 1 or vim.fn.filereadable(new_path) == 1 then
      vim.notify('mep.filetree: ' .. new_path .. ' already exists', vim.log.levels.ERROR)
      return
    end
    if vim.fn.rename(node.path, new_path) ~= 0 then
      vim.notify('mep.filetree: failed to rename ' .. node.path, vim.log.levels.ERROR)
      return
    end

    invalidate_and_render(node.parent)
    set_cursor_to_node(find_node_by_path(new_path))
  end)
end

--- Delete the node under the cursor, after confirming ('&Yes\n&No',
--- defaulting to "No" — same confirm() shape as mep.git's discard-changes
--- prompt). Directories are removed recursively. Refuses to delete the
--- tree root; moves the cursor to the parent directory afterward.
local function delete_node()
  local node = node_at_cursor()
  if not node then
    return
  end
  if not node.parent then
    vim.notify('mep.filetree: cannot delete the tree root', vim.log.levels.WARN)
    return
  end

  if vim.fn.confirm('Delete ' .. node.name .. '?', '&Yes\n&No', 2) ~= 1 then
    return
  end
  if vim.fn.delete(node.path, node.is_dir and 'rf' or '') ~= 0 then
    vim.notify('mep.filetree: failed to delete ' .. node.path, vim.log.levels.ERROR)
    return
  end

  local parent = node.parent
  invalidate_and_render(parent)
  set_cursor_to_node(parent)
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

--- Every keymap this panel binds, `lhs`/`fn`/`desc` per entry — the one
--- source both `bind_keymaps` and the `?` help popup read from, so the
--- two can never drift apart. A function (not a static table) since it
--- reads `config.options.keymaps`, which can change across a re-`setup()`
--- between one `open()` and the next.
local function action_list()
  local keymaps = config.options.keymaps
  return {
    { lhs = keymaps.open, fn = open_node, desc = 'Open file / toggle directory' },
    { lhs = keymaps.expand, fn = expand_node, desc = 'Expand directory' },
    { lhs = keymaps.collapse, fn = collapse_node, desc = 'Collapse directory / go to parent' },
    { lhs = keymaps.add, fn = add_node, desc = 'Create a new file/directory' },
    { lhs = keymaps.rename, fn = rename_node, desc = 'Rename the file/directory under the cursor' },
    { lhs = keymaps.delete, fn = delete_node, desc = 'Delete the file/directory under the cursor (confirms first)' },
    { lhs = keymaps.refresh, fn = M.refresh, desc = 'Refresh the file tree' },
    { lhs = keymaps.close, fn = M.close, desc = 'Close the file tree' },
    { lhs = keymaps.help, fn = M.toggle_help, desc = 'Toggle this help' },
  }
end

local help_win = nil

local function close_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end
  help_win = nil
end

local function help_lines()
  local key_col_width = 0
  local rows = {}
  for _, a in ipairs(action_list()) do
    if #a.lhs > 0 then
      local keys = table.concat(a.lhs, ' / ')
      rows[#rows + 1] = { keys, a.desc }
      key_col_width = math.max(key_col_width, vim.fn.strdisplaywidth(keys))
    end
  end
  local lines = {}
  for _, r in ipairs(rows) do
    lines[#lines + 1] = string.format('%-' .. key_col_width .. 's  %s', r[1], r[2])
  end
  return lines
end

--- Toggle a floating popup listing every keymap this panel currently has
--- bound (see `action_list`) — dismiss with `q`/`<Esc>`/`?` again, same
--- as `mep.org.tags.select_interactive`'s own popup.
function M.toggle_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    close_help()
    return
  end
  if not is_open() then
    return
  end

  local lines = help_lines()
  local width = 8
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].modifiable = false

  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = #lines,
    style = 'minimal',
    border = 'rounded',
    title = ' mep.filetree keymaps ',
    title_pos = 'center',
  })

  local map_opts = { buffer = help_buf, nowait = true, silent = true }
  vim.keymap.set('n', 'q', close_help, map_opts)
  vim.keymap.set('n', '<Esc>', close_help, map_opts)
  vim.keymap.set('n', '?', close_help, map_opts)
end

local function bind_keymaps()
  local map_opts = { buffer = state.buf, silent = true, nowait = true }
  for _, a in ipairs(action_list()) do
    local opts = vim.tbl_extend('force', map_opts, { desc = a.desc })
    for _, lhs in ipairs(a.lhs) do
      vim.keymap.set('n', lhs, a.fn, opts)
    end
  end
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
  close_help()
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

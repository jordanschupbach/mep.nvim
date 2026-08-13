--- Pure tree data structure for mep.filetree: nodes are scanned lazily
--- (a directory's `children` stay `nil` until it's expanded), one level
--- at a time, so opening a huge project tree doesn't walk the whole
--- filesystem up front. No window/buffer code lives here — see ui.lua for
--- rendering.
local uv = vim.uv or vim.loop

local M = {}

--- A fresh root node for `path`, expanded by default (so the top level is
--- visible as soon as the tree opens). Children are NOT loaded yet — call
--- `ensure_children` or `ensure_expanded_loaded`.
function M.new_root(path)
  return {
    path = path,
    name = vim.fn.fnamemodify(path, ':t'),
    is_dir = true,
    expanded = true,
    depth = 0,
    children = nil,
  }
end

local function scan_children(dir_path, show_hidden)
  local dirs, files = {}, {}
  local fd = uv.fs_scandir(dir_path)
  if not fd then
    return {}
  end
  while true do
    local name, typ = uv.fs_scandir_next(fd)
    if not name then
      break
    end
    if show_hidden or not vim.startswith(name, '.') then
      local entry = { name = name, path = dir_path .. '/' .. name }
      if typ == 'directory' then
        entry.is_dir = true
        entry.expanded = false
        table.insert(dirs, entry)
      elseif typ == 'file' then
        entry.is_dir = false
        table.insert(files, entry)
      end
    end
  end
  table.sort(dirs, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  table.sort(files, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  local children = {}
  for _, d in ipairs(dirs) do
    children[#children + 1] = d
  end
  for _, f in ipairs(files) do
    children[#children + 1] = f
  end
  return children
end

--- Populate `node.children` (directories first, then files, both
--- alphabetical) if not already loaded. No-op for files or already-loaded
--- directories.
function M.ensure_children(node, show_hidden)
  if not node.is_dir or node.children ~= nil then
    return
  end
  node.children = scan_children(node.path, show_hidden)
  for _, child in ipairs(node.children) do
    child.depth = node.depth + 1
    child.parent = node
  end
end

--- Flip a directory's expanded state, loading its children the first time
--- it's expanded. No-op for files.
function M.toggle_expand(node, show_hidden)
  if not node.is_dir then
    return
  end
  node.expanded = not node.expanded
  if node.expanded then
    M.ensure_children(node, show_hidden)
  end
end

--- Walk the tree and make sure every currently-expanded directory has its
--- children loaded (recursively) — call before flattening/rendering so
--- a refresh (which invalidates caches without collapsing anything)
--- re-populates automatically.
function M.ensure_expanded_loaded(root, show_hidden)
  local function walk(node)
    if node.is_dir and node.expanded then
      M.ensure_children(node, show_hidden)
      if node.children then
        for _, child in ipairs(node.children) do
          walk(child)
        end
      end
    end
  end
  walk(root)
end

--- Recursively clear cached `children` on every directory node (without
--- touching `expanded`), forcing a fresh scan on the next
--- `ensure_expanded_loaded` pass. Used by refresh.
function M.invalidate(node)
  if not node.is_dir then
    return
  end
  local children = node.children
  node.children = nil
  if children then
    for _, child in ipairs(children) do
      M.invalidate(child)
    end
  end
end

--- Flatten the tree into an ordered list of currently-visible nodes (the
--- root, plus descendants of expanded directories) — one entry per
--- rendered line.
function M.flatten(root)
  local out = {}
  local function walk(node)
    out[#out + 1] = node
    if node.is_dir and node.expanded and node.children then
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end
  walk(root)
  return out
end

return M

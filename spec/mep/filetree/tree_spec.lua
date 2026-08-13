local tree = require('mep.filetree.tree')

local function mktemp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(content or '')
  f:close()
end

describe('mep.filetree.tree', function()
  describe('new_root', function()
    it('creates an expanded root node with no children loaded yet', function()
      local root = tree.new_root('/some/project')
      assert.are.equal('/some/project', root.path)
      assert.are.equal('project', root.name)
      assert.is_true(root.is_dir)
      assert.is_true(root.expanded)
      assert.are.equal(0, root.depth)
      assert.is_nil(root.children)
    end)
  end)

  describe('ensure_children', function()
    local root

    before_each(function()
      root = mktemp_dir()
      write_file(root .. '/b.txt', '')
      write_file(root .. '/a.txt', '')
      vim.fn.mkdir(root .. '/zdir', 'p')
      vim.fn.mkdir(root .. '/adir', 'p')
      write_file(root .. '/.hidden', '')
    end)

    after_each(function()
      vim.fn.delete(root, 'rf')
    end)

    it('lists directories first, then files, both alphabetical, skipping dotfiles by default', function()
      local node = tree.new_root(root)
      tree.ensure_children(node, false)

      local names = {}
      for _, c in ipairs(node.children) do
        names[#names + 1] = c.name
      end
      assert.are.same({ 'adir', 'zdir', 'a.txt', 'b.txt' }, names)
    end)

    it('includes dotfiles when show_hidden is true', function()
      local node = tree.new_root(root)
      tree.ensure_children(node, true)

      local has_hidden = false
      for _, c in ipairs(node.children) do
        if c.name == '.hidden' then
          has_hidden = true
        end
      end
      assert.is_true(has_hidden)
    end)

    it('sets depth and parent on each child', function()
      local node = tree.new_root(root)
      tree.ensure_children(node, false)

      for _, c in ipairs(node.children) do
        assert.are.equal(1, c.depth)
        assert.are.equal(node, c.parent)
      end
    end)

    it('marks directory children as collapsed dirs and file children as files', function()
      local node = tree.new_root(root)
      tree.ensure_children(node, false)

      assert.is_true(node.children[1].is_dir)
      assert.is_false(node.children[1].expanded)
      assert.is_false(node.children[3].is_dir)
    end)

    it('is a no-op once children are already loaded', function()
      local node = tree.new_root(root)
      tree.ensure_children(node, false)
      local first = node.children

      write_file(root .. '/new_after_load.txt', '')
      tree.ensure_children(node, false)

      assert.are.equal(first, node.children) -- same table, not rescanned
    end)
  end)

  describe('toggle_expand', function()
    it('flips expanded and loads children the first time a directory expands', function()
      local root = mktemp_dir()
      write_file(root .. '/f.txt', '')
      local node = tree.new_root(root)
      node.expanded = false

      tree.toggle_expand(node, false)
      assert.is_true(node.expanded)
      assert.is_not_nil(node.children)

      tree.toggle_expand(node, false)
      assert.is_false(node.expanded)
      assert.is_not_nil(node.children) -- collapsing doesn't drop the cache

      vim.fn.delete(root, 'rf')
    end)

    it('is a no-op for files', function()
      local file_node = { is_dir = false, expanded = nil }
      tree.toggle_expand(file_node, false)
      assert.is_nil(file_node.expanded)
    end)
  end)

  describe('ensure_expanded_loaded', function()
    it('recursively loads children for every already-expanded directory', function()
      local root_path = mktemp_dir()
      vim.fn.mkdir(root_path .. '/sub', 'p')
      write_file(root_path .. '/sub/deep.txt', '')

      local root = tree.new_root(root_path)
      tree.ensure_children(root, false)
      local sub = root.children[1]
      sub.expanded = true -- pre-expanded, children not loaded yet

      tree.ensure_expanded_loaded(root, false)

      assert.is_not_nil(sub.children)
      assert.are.equal('deep.txt', sub.children[1].name)

      vim.fn.delete(root_path, 'rf')
    end)

    it('does not load children for collapsed directories', function()
      local root_path = mktemp_dir()
      vim.fn.mkdir(root_path .. '/sub', 'p')

      local root = tree.new_root(root_path)
      tree.ensure_children(root, false)
      local sub = root.children[1]
      assert.is_false(sub.expanded)

      tree.ensure_expanded_loaded(root, false)
      assert.is_nil(sub.children)

      vim.fn.delete(root_path, 'rf')
    end)
  end)

  describe('invalidate', function()
    it('clears cached children recursively but keeps expanded flags', function()
      local root_path = mktemp_dir()
      vim.fn.mkdir(root_path .. '/sub', 'p')

      local root = tree.new_root(root_path)
      tree.ensure_children(root, false)
      local sub = root.children[1]
      sub.expanded = true
      tree.ensure_children(sub, false)

      tree.invalidate(root)

      assert.is_nil(root.children)
      assert.is_true(sub.expanded) -- expand state survives invalidation

      vim.fn.delete(root_path, 'rf')
    end)

    it('a subsequent ensure_expanded_loaded picks up filesystem changes', function()
      local root_path = mktemp_dir()
      local root = tree.new_root(root_path)
      tree.ensure_children(root, false)
      assert.are.equal(0, #root.children)

      write_file(root_path .. '/new.txt', '')
      tree.invalidate(root)
      tree.ensure_expanded_loaded(root, false)

      assert.are.equal(1, #root.children)
      assert.are.equal('new.txt', root.children[1].name)

      vim.fn.delete(root_path, 'rf')
    end)
  end)

  describe('flatten', function()
    it('includes only the root when nothing is expanded', function()
      local root = { name = 'root', is_dir = true, expanded = false, children = {
        { name = 'child', is_dir = false },
      } }
      local flat = tree.flatten(root)
      assert.are.equal(1, #flat)
      assert.are.equal(root, flat[1])
    end)

    it('includes descendants of expanded directories, in child order, depth-first', function()
      local file_a = { name = 'a.txt', is_dir = false }
      local subdir = {
        name = 'sub',
        is_dir = true,
        expanded = true,
        children = { { name = 'deep.txt', is_dir = false } },
      }
      local root = {
        name = 'root',
        is_dir = true,
        expanded = true,
        children = { subdir, file_a },
      }

      local flat = tree.flatten(root)
      local names = {}
      for _, n in ipairs(flat) do
        names[#names + 1] = n.name
      end
      assert.are.same({ 'root', 'sub', 'deep.txt', 'a.txt' }, names)
    end)

    it('excludes descendants of a collapsed directory even if it has cached children', function()
      local subdir = {
        name = 'sub',
        is_dir = true,
        expanded = false,
        children = { { name = 'hidden.txt', is_dir = false } },
      }
      local root = { name = 'root', is_dir = true, expanded = true, children = { subdir } }

      local flat = tree.flatten(root)
      local names = {}
      for _, n in ipairs(flat) do
        names[#names + 1] = n.name
      end
      assert.are.same({ 'root', 'sub' }, names)
    end)
  end)
end)

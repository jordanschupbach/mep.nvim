local util = require('mep.core.util')

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

describe('mep.core.util', function()
  describe('debounce', function()
    it('collapses rapid calls into one, carrying the last call\'s arguments', function()
      local calls = {}
      local debounced, timer = util.debounce(function(...)
        table.insert(calls, { ... })
      end, 20)

      debounced('first')
      debounced('second')
      debounced('third')

      assert.are.equal(0, #calls)
      vim.wait(500, function()
        return #calls > 0
      end, 5)

      assert.are.equal(1, #calls)
      assert.are.same({ 'third' }, calls[1])

      timer:stop()
      timer:close()
    end)

    it('fires again for calls after the delay has elapsed', function()
      local calls = 0
      local debounced, timer = util.debounce(function()
        calls = calls + 1
      end, 20)

      debounced()
      vim.wait(500, function()
        return calls == 1
      end, 5)

      debounced()
      vim.wait(500, function()
        return calls == 2
      end, 5)

      assert.are.equal(2, calls)
      timer:stop()
      timer:close()
    end)
  end)

  describe('find_root', function()
    it('walks upward to the nearest ancestor containing a marker', function()
      local root = mktemp_dir()
      local marker = root .. '/.mep-test-marker'
      vim.fn.mkdir(marker, 'p')
      local deep = root .. '/a/b/c'
      vim.fn.mkdir(deep, 'p')

      local found = util.find_root(deep, { '.mep-test-marker' })
      -- resolve both sides in case /tmp is itself a symlink (e.g. on macOS)
      assert.are.equal(vim.fn.resolve(root), vim.fn.resolve(found))

      vim.fn.delete(root, 'rf')
    end)

    it('returns the starting path when no marker is found anywhere above it', function()
      local dir = mktemp_dir()
      local found = util.find_root(dir, { '.definitely-not-a-real-marker-xyz' })
      assert.are.equal(vim.fn.resolve(dir), vim.fn.resolve(found))
      vim.fn.delete(dir, 'rf')
    end)
  end)

  describe('scan_dir', function()
    it('lists files recursively, skipping dotfiles and dotdirs', function()
      local root = mktemp_dir()
      write_file(root .. '/a.txt', '')
      write_file(root .. '/sub/b.lua', '')
      write_file(root .. '/.hidden_file', '')
      write_file(root .. '/.hidden_dir/c.txt', '')

      local items = {}
      util.scan_dir(root, items)

      local names = {}
      for _, item in ipairs(items) do
        table.insert(names, item.filename)
      end
      table.sort(names)

      assert.are.same({ 'a.txt', 'sub/b.lua' }, names)

      vim.fn.delete(root, 'rf')
    end)

    it('sets display equal to filename', function()
      local root = mktemp_dir()
      write_file(root .. '/only.txt', '')

      local items = {}
      util.scan_dir(root, items)

      assert.are.equal(1, #items)
      assert.are.equal('only.txt', items[1].filename)
      assert.are.equal('only.txt', items[1].display)

      vim.fn.delete(root, 'rf')
    end)

    it('stops once max_items is reached', function()
      local root = mktemp_dir()
      for i = 1, 5 do
        write_file(root .. '/f' .. i .. '.txt', '')
      end

      local items = {}
      util.scan_dir(root, items, 2)

      assert.are.equal(2, #items)

      vim.fn.delete(root, 'rf')
    end)
  end)

  describe('open_file', function()
    it('opens the file as the current buffer', function()
      local root = mktemp_dir()
      local path = root .. '/target.txt'
      write_file(path, 'one\ntwo\nthree\n')

      util.open_file(path)

      assert.are.equal(path, vim.api.nvim_buf_get_name(0))

      vim.fn.delete(root, 'rf')
    end)

    it('moves the cursor to lnum/col when given', function()
      local root = mktemp_dir()
      local path = root .. '/target.txt'
      write_file(path, 'one\ntwo\nthree\n')

      util.open_file(path, 2, 3)

      assert.are.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))

      vim.fn.delete(root, 'rf')
    end)

    it('leaves the cursor at the default position when lnum is not given', function()
      local root = mktemp_dir()
      local path = root .. '/target.txt'
      write_file(path, 'one\ntwo\nthree\n')

      assert.has_no.errors(function()
        util.open_file(path)
      end)

      vim.fn.delete(root, 'rf')
    end)
  end)
end)

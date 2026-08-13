local include = require('mep.org.include')

local function write_tmp(lines)
  local path = vim.fn.tempname() .. '.org'
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.org.include', function()
  describe('resolve_lines', function()
    it('splices in a whole included file', function()
      local child = write_tmp({ 'child line 1', 'child line 2' })
      local lines = { 'before', '#+INCLUDE: "' .. child .. '"', 'after' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same({ 'before', 'child line 1', 'child line 2', 'after' }, resolved)
      vim.fn.delete(child)
    end)

    it('resolves a relative path against base_dir', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'relative content' }, dir .. '/child.org')
      local lines = { '#+INCLUDE: "child.org"' }
      local resolved = include.resolve_lines(lines, dir)
      assert.are.same({ 'relative content' }, resolved)
      vim.fn.delete(dir, 'rf')
    end)

    it('selects a :lines "M-N" range', function()
      local child = write_tmp({ 'l1', 'l2', 'l3', 'l4' })
      local lines = { '#+INCLUDE: "' .. child .. '" :lines "2-3"' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same({ 'l2', 'l3' }, resolved)
      vim.fn.delete(child)
    end)

    it('supports an open-ended :lines range', function()
      local child = write_tmp({ 'l1', 'l2', 'l3' })
      local lines = { '#+INCLUDE: "' .. child .. '" :lines "2-"' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same({ 'l2', 'l3' }, resolved)
      vim.fn.delete(child)
    end)

    it('wraps content in a src block for "src lang"', function()
      local child = write_tmp({ 'print(1)' })
      local lines = { '#+INCLUDE: "' .. child .. '" src lua' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same({ '#+begin_src lua', 'print(1)', '#+end_src' }, resolved)
      vim.fn.delete(child)
    end)

    it('resolves nested includes recursively', function()
      local grandchild = write_tmp({ 'deepest' })
      local child = write_tmp({ 'mid', '#+INCLUDE: "' .. grandchild .. '"' })
      local lines = { '#+INCLUDE: "' .. child .. '"' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same({ 'mid', 'deepest' }, resolved)
      vim.fn.delete(child)
      vim.fn.delete(grandchild)
    end)

    it('leaves the directive untouched with a warning for a missing file', function()
      local lines = { '#+INCLUDE: "/no/such/file.org"' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same(lines, resolved)
    end)

    it('detects a self-referencing cycle without hanging', function()
      local path = vim.fn.tempname() .. '.org'
      vim.fn.writefile({ '#+INCLUDE: "' .. path .. '"' }, path)
      local lines = { '#+INCLUDE: "' .. path .. '"' }
      local resolved = include.resolve_lines(lines, '/tmp')
      assert.are.same(lines, resolved)
      vim.fn.delete(path)
    end)

    it('passes through lines with no INCLUDE directive unchanged', function()
      local lines = { 'a', 'b', 'c' }
      assert.are.same(lines, include.resolve_lines(lines, '/tmp'))
    end)
  end)

  describe('resolve', function()
    it('resolves includes relative to the buffer file directory', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'child content' }, dir .. '/child.org')
      local bufpath = dir .. '/main.org'
      vim.fn.writefile({ '#+INCLUDE: "child.org"' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)
      assert.are.same({ 'child content' }, include.resolve(buf))
      vim.fn.delete(dir, 'rf')
    end)
  end)
end)

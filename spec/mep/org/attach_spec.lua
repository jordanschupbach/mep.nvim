local attach = require('mep.org.attach')

local function make_file_buf(dir, name, lines)
  local path = dir .. '/' .. name
  vim.fn.writefile(lines, path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  return buf
end

describe('mep.org.attach', function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  describe('dir_for', function()
    it('derives a directory from a 2/rest split of the headline ID', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task', ':PROPERTIES:', ':ID: abcdef12-3456', ':END:' })
      local path = attach.dir_for(buf, 1, nil, false)
      assert.are.equal(dir .. '/data/ab/cdef12-3456/', path)
    end)

    it('creates an :ID: property if the headline has none', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task' })
      local path = attach.dir_for(buf, 1, nil, false)
      assert.is_not_nil(path)
      assert.is_not_nil(path:match('^' .. vim.pesc(dir .. '/data/')))
    end)

    it('creates the directory on disk when create=true', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task' })
      local path = attach.dir_for(buf, 1, nil, true)
      assert.are.equal(1, vim.fn.isdirectory(path))
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_file_buf(dir, 'notes.org', { 'no headline' })
      assert.is_nil(attach.dir_for(buf, 1, nil, false))
    end)

    it('honors a custom root', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task', ':PROPERTIES:', ':ID: abcdef12', ':END:' })
      local path = attach.dir_for(buf, 1, 'attachments', false)
      assert.are.equal(dir .. '/attachments/ab/cdef12/', path)
    end)
  end)

  describe('attach / list', function()
    it('copies a file into the attachment directory', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task' })
      local src = dir .. '/source.txt'
      vim.fn.writefile({ 'hello' }, src)

      local dest = attach.attach(buf, 1, src)
      assert.is_not_nil(dest)
      assert.are.equal(1, vim.fn.filereadable(dest))
      assert.are.same({ 'hello' }, vim.fn.readfile(dest))
      assert.are.same({ 'source.txt' }, attach.list(buf, 1))
    end)

    it('returns nil with a warning when the source is unreadable', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task' })
      assert.is_nil(attach.attach(buf, 1, dir .. '/nope.txt'))
    end)

    it('list returns an empty table when nothing is attached yet', function()
      local buf = make_file_buf(dir, 'notes.org', { '* Task' })
      assert.are.same({}, attach.list(buf, 1))
    end)
  end)
end)

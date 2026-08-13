local archive = require('mep.org.archive')

local function make_buf(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.archive', function()
  local tmpdir

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
  end)

  after_each(function()
    vim.fn.delete(tmpdir, 'rf')
  end)

  describe('default_archive_path', function()
    it('strips the extension and appends _archive.org', function()
      local buf = make_buf(tmpdir .. '/notes.org', { '* x' })
      assert.are.equal(tmpdir .. '/notes_archive.org', archive.default_archive_path(buf))
    end)

    it('falls back to archive.org in the cwd for an unnamed buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.are.equal(vim.fn.getcwd() .. '/archive.org', archive.default_archive_path(buf))
    end)
  end)

  describe('archive_subtree', function()
    it('removes the subtree from the source buffer', function()
      local buf = make_buf(tmpdir .. '/notes.org', {
        '* Keep',
        '* Drop me',
        'drop body',
        '* Also keep',
      })
      archive.archive_subtree(buf, 2)
      assert.are.same({ '* Keep', '* Also keep' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('writes the subtree to the archive file with a properties drawer', function()
      local buf = make_buf(tmpdir .. '/notes.org', { '* Drop me', 'drop body' })
      local path = archive.archive_subtree(buf, 1)
      assert.are.equal(tmpdir .. '/notes_archive.org', path)
      assert.are.equal(1, vim.fn.filereadable(path))

      local written = vim.fn.readfile(path)
      assert.are.equal('* Drop me', written[1])
      assert.are.equal(':PROPERTIES:', written[2])
      assert.matches('^:ARCHIVE_TIME:', written[3])
      assert.matches('^:ARCHIVE_FILE:', written[4])
      assert.are.equal(':END:', written[5])
      assert.are.equal('drop body', written[6])
    end)

    it('appends to an existing archive file rather than overwriting it', function()
      local shared_archive = tmpdir .. '/shared_archive.org'
      local buf1 = make_buf(tmpdir .. '/notes1.org', { '* First' })
      archive.archive_subtree(buf1, 1, shared_archive)

      local buf2 = make_buf(tmpdir .. '/notes2.org', { '* Second' })
      archive.archive_subtree(buf2, 1, shared_archive)

      local written = vim.fn.readfile(shared_archive)
      assert.are.equal('* First', written[1])
      assert.are.equal('* Second', written[6])
    end)

    it('honors an explicit archive_path override', function()
      local buf = make_buf(tmpdir .. '/notes.org', { '* Drop me' })
      local custom = tmpdir .. '/custom.org'
      local path = archive.archive_subtree(buf, 1, custom)
      assert.are.equal(custom, path)
      assert.are.equal(1, vim.fn.filereadable(custom))
    end)

    it('creates the archive directory if it does not exist yet', function()
      local buf = make_buf(tmpdir .. '/notes.org', { '* Drop me' })
      local nested = tmpdir .. '/nested/dir/archive.org'
      local path = archive.archive_subtree(buf, 1, nested)
      assert.are.equal(1, vim.fn.filereadable(path))
    end)

    it('returns nil and touches nothing when lnum is not inside a headline', function()
      local buf = make_buf(tmpdir .. '/notes.org', { 'no headline' })
      assert.is_nil(archive.archive_subtree(buf, 1))
      assert.are.same({ 'no headline' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)
end)

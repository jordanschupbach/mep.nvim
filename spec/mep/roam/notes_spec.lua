local notes = require('mep.roam.notes')

local scratch_dir = '/tmp/mep-roam-notes-spec'

local function write_file(rel, lines)
  local path = scratch_dir .. '/' .. rel
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.roam.notes', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('title', function()
    it('prefers #+TITLE: over the first headline', function()
      local path = write_file('a.org', { '#+TITLE: Real Title', '* Headline Title' })
      assert.are.equal('Real Title', notes.title(notes.load_buf(path)))
    end)

    it('falls back to the first headline title', function()
      local path = write_file('b.org', { '* Headline Title', 'body' })
      assert.are.equal('Headline Title', notes.title(notes.load_buf(path)))
    end)

    it('falls back to the bare filename when there is neither', function()
      local path = write_file('c.org', { 'just text' })
      assert.are.equal('c', notes.title(notes.load_buf(path)))
    end)
  end)

  describe('id', function()
    it('assigns a fresh ID to the first headline if it has none', function()
      local path = write_file('d.org', { '* A Note' })
      local bufnr = notes.load_buf(path)
      local id = notes.id(bufnr)
      assert.is_not_nil(id)
      assert.matches('^%x+%-%x+%-4%x+%-%x+%-%x+$', id)
    end)

    it('reuses an existing ID rather than generating a new one', function()
      local path = write_file('e.org', { '* A Note', ':PROPERTIES:', ':ID: fixed-id', ':END:' })
      local bufnr = notes.load_buf(path)
      assert.are.equal('fixed-id', notes.id(bufnr))
    end)

    it('returns nil for a file with no headline at all', function()
      local path = write_file('f.org', { 'no headline here' })
      assert.is_nil(notes.id(notes.load_buf(path)))
    end)
  end)

  describe('files', function()
    it('finds .org files recursively under roam_dirs, deduped and sorted', function()
      write_file('z.org', { '* Z' })
      write_file('sub/a.org', { '* A' })
      local files = notes.files({ scratch_dir })
      assert.are.same({ scratch_dir .. '/sub/a.org', scratch_dir .. '/z.org' }, files)
    end)

    it('returns {} for no configured directories', function()
      assert.are.same({}, notes.files({}))
      assert.are.same({}, notes.files(nil))
    end)
  end)

  describe('list', function()
    it('lists every note with a headline, sorted by title', function()
      write_file('g.org', { '#+TITLE: Zeta', '* H' })
      write_file('h.org', { '#+TITLE: Alpha', '* H' })
      local list = notes.list({ scratch_dir })
      assert.are.equal(2, #list)
      assert.are.equal('Alpha', list[1].title)
      assert.are.equal('Zeta', list[2].title)
      assert.is_not_nil(list[1].id)
    end)

    it('skips a file with no headline (nothing to anchor an ID on)', function()
      write_file('i.org', { 'no headline' })
      assert.are.same({}, notes.list({ scratch_dir }))
    end)
  end)
end)

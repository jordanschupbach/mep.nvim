local finder = require('mep.bib.finder')

local function make_buf_at(path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, path)
  return buf
end

describe('mep.bib.finder', function()
  local tmp

  before_each(function()
    tmp = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmp .. '/.git', 'p')
    vim.fn.mkdir(tmp .. '/sub', 'p')
  end)

  after_each(function()
    vim.fn.delete(tmp, 'rf')
  end)

  it('finds a .bib file in the buffer\'s own directory', function()
    vim.fn.writefile({ '@article{x, title = {T}}' }, tmp .. '/sub/refs.bib')
    local buf = make_buf_at(tmp .. '/sub/notes.org')

    local found = finder.find_bib_files(buf)
    assert.are.equal(1, #found)
    assert.matches('refs%.bib$', found[1])
  end)

  it('short-circuits at the buffer directory, ignoring the project root even if it also has one', function()
    vim.fn.writefile({ '@article{x, title = {T}}' }, tmp .. '/sub/local.bib')
    vim.fn.writefile({ '@article{y, title = {T2}}' }, tmp .. '/root.bib')
    local buf = make_buf_at(tmp .. '/sub/notes.org')

    local found = finder.find_bib_files(buf)
    assert.are.equal(1, #found)
    assert.matches('local%.bib$', found[1])
  end)

  it('falls back to the project root when the buffer\'s own directory has none', function()
    vim.fn.writefile({ '@article{y, title = {T2}}' }, tmp .. '/root.bib')
    local buf = make_buf_at(tmp .. '/sub/notes.org')

    local found = finder.find_bib_files(buf)
    assert.are.equal(1, #found)
    assert.matches('root%.bib$', found[1])
  end)

  it('returns an empty list when neither location has a .bib file', function()
    local buf = make_buf_at(tmp .. '/sub/notes.org')
    assert.are.same({}, finder.find_bib_files(buf))
  end)

  it('lists every .bib file when a directory has more than one', function()
    vim.fn.writefile({ '@article{a, title = {A}}' }, tmp .. '/sub/a.bib')
    vim.fn.writefile({ '@article{b, title = {B}}' }, tmp .. '/sub/b.bib')
    local buf = make_buf_at(tmp .. '/sub/notes.org')

    assert.are.equal(2, #finder.find_bib_files(buf))
  end)
end)

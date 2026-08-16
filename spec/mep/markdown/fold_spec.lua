local fold = require('mep.markdown.fold')

describe('mep.markdown.fold', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function foldexpr_at(lnum)
    vim.v.lnum = lnum
    return fold.foldexpr()
  end

  it('starts a new fold at a heading, keyed by its level', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', '## H2', '### H3' })
    assert.are.equal('>1', foldexpr_at(1))
    assert.are.equal('>2', foldexpr_at(2))
    assert.are.equal('>3', foldexpr_at(3))
  end)

  it('inherits the nearest enclosing heading level for body text', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', 'body under h1', '## H2', 'body under h2' })
    assert.are.equal(1, foldexpr_at(2))
    assert.are.equal(2, foldexpr_at(4))
  end)

  it('treats 7+ leading #s as not a heading (CommonMark)', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', '####### not a heading' })
    assert.are.equal(1, foldexpr_at(2))
  end)

  it('returns 0 for content before any heading', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'preamble text', '# H1' })
    assert.are.equal(0, foldexpr_at(1))
  end)

  it('nests a fenced code block one level deeper than its section', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', '```lua', 'local x = 1', '```', 'after' })
    assert.are.equal('>2', foldexpr_at(2)) -- opening fence starts the nested fold
    assert.are.equal(2, foldexpr_at(3)) -- inside the fence
    assert.are.equal(2, foldexpr_at(4)) -- closing fence
    assert.are.equal(1, foldexpr_at(5)) -- back to the section level after
  end)

  it('extends an unclosed fence through the end of the buffer', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', '```lua', 'local x = 1' })
    assert.are.equal('>2', foldexpr_at(2))
    assert.are.equal(2, foldexpr_at(3))
  end)

  it('supports ~~~ fences the same way as ```', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# H1', '~~~', 'code', '~~~' })
    assert.are.equal('>2', foldexpr_at(2))
    assert.are.equal(2, foldexpr_at(3))
  end)
end)

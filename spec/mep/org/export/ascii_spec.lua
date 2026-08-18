local export = require('mep.org.export')
local ascii = require('mep.org.export.ascii')

local function render(lines, opts)
  opts = opts or {}
  opts.todo_keywords = opts.todo_keywords or { 'TODO', 'DONE' }
  if opts.eval == nil then
    opts.eval = false -- these tests check rendering shape, not babel execution
  end
  local doc = export.parse_lines(lines, opts)
  return ascii.render(doc)
end

describe('mep.org.export.ascii', function()
  it('underlines a level-1 headline with =', function()
    local out = render({ '* Title' })
    local idx
    for i, l in ipairs(out) do
      if l == '1. Title' then
        idx = i
      end
    end
    assert.is_not_nil(idx)
    assert.are.equal(string.rep('=', #out[idx]), out[idx + 1])
  end)

  it('underlines a level-2 headline with -', function()
    local out = render({ '* Top', '** Sub' })
    local idx
    for i, l in ipairs(out) do
      if l:match('^1%.1%. Sub') then
        idx = i
      end
    end
    assert.is_not_nil(idx)
    assert.are.equal(string.rep('-', #out[idx]), out[idx + 1])
  end)

  it('keeps emphasis markers literal', function()
    local out = render({ 'a *bold* word' })
    assert.is_true(vim.tbl_contains(out, 'a *bold* word'))
  end)

  it('renders a link as "description (target)"', function()
    local out = render({ 'see [[https://x.com][X]] now' })
    assert.is_true(vim.tbl_contains(out, 'see X (https://x.com) now'))
  end)

  it('renders a bare link as its target', function()
    local out = render({ '[[https://x.com]]' })
    assert.is_true(vim.tbl_contains(out, 'https://x.com'))
  end)

  it('renders a checkbox list item', function()
    local out = render({ '- [X] done', '- [ ] todo' })
    assert.is_true(vim.tbl_contains(out, '- [X] done'))
    assert.is_true(vim.tbl_contains(out, '- [ ] todo'))
  end)

  it('nests list items with 2-space indent per depth', function()
    local out = render({ '- top', '  - nested' })
    assert.is_true(vim.tbl_contains(out, '- top'))
    assert.is_true(vim.tbl_contains(out, '  - nested'))
  end)

  it('numbers a plain ordered list from 1', function()
    local out = render({ '1. a', '1. b', '1. c' })
    assert.is_true(vim.tbl_contains(out, '1. a'))
    assert.is_true(vim.tbl_contains(out, '2. b'))
    assert.is_true(vim.tbl_contains(out, '3. c'))
  end)

  it('indents a src block body by 4 spaces', function()
    local out = render({ '#+begin_src lua', 'print(1)', '#+end_src' })
    assert.is_true(vim.tbl_contains(out, '    print(1)'))
  end)

  it('prefixes babel results with ": ", after the indented code', function()
    local doc = { footnotes = {}, options = {}, blocks = { { type = 'src', lang = 'lua', body = { 'print(1)' }, results = { '1' }, show_code = true } } }
    local out = ascii.render(doc)
    assert.is_true(vim.tbl_contains(out, '    print(1)'))
    assert.is_true(vim.tbl_contains(out, ': 1'))
  end)

  it('omits the indented code when show_code is false (:exports results)', function()
    local doc = { footnotes = {}, options = {}, blocks = { { type = 'src', lang = 'lua', body = { 'print(1)' }, results = { '1' }, show_code = false } } }
    local out = ascii.render(doc)
    assert.is_false(vim.tbl_contains(out, '    print(1)'))
    assert.is_true(vim.tbl_contains(out, ': 1'))
  end)

  it('prefixes an example block body with ": "', function()
    local out = render({ '#+BEGIN_EXAMPLE', 'raw', '#+END_EXAMPLE' })
    assert.is_true(vim.tbl_contains(out, ': raw'))
  end)

  it('includes a title header when #+TITLE: is set', function()
    local out = render({ '#+TITLE: My Doc', '#+AUTHOR: Jordan', 'body' })
    assert.are.equal('My Doc', out[1])
    assert.are.equal(string.rep('=', #'My Doc'), out[2])
    assert.are.equal('Author: Jordan', out[3])
  end)

  it('includes a table of contents by default', function()
    local out = render({ '* One', '** Two' })
    assert.is_true(vim.tbl_contains(out, 'Table of Contents'))
  end)

  it('omits the table of contents when toc:nil', function()
    local out = render({ '#+OPTIONS: toc:nil', '* One' })
    assert.is_false(vim.tbl_contains(out, 'Table of Contents'))
  end)

  it('renders a footnotes section at the bottom', function()
    local out = render({ 'see[fn:a]', '[fn:a] the note' })
    assert.is_true(vim.tbl_contains(out, 'Footnotes'))
    assert.is_true(vim.tbl_contains(out, '[a] the note'))
  end)

  it('renders a headline with TODO/priority/tags', function()
    local out = render({ '* TODO [#A] Buy milk :errand:' })
    assert.is_true(vim.tbl_contains(out, '1. TODO [#A] Buy milk  :errand:'))
  end)
end)

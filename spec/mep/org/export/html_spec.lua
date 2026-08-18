local export = require('mep.org.export')
local html = require('mep.org.export.html')

local function render(lines, opts)
  opts = opts or {}
  opts.todo_keywords = opts.todo_keywords or { 'TODO', 'DONE' }
  if opts.eval == nil then
    opts.eval = false -- these tests check rendering shape, not babel execution
  end
  local doc = export.parse_lines(lines, opts)
  return html.render(doc)
end

local function joined(lines)
  return table.concat(render(lines), '\n')
end

describe('mep.org.export.html', function()
  it('maps headline level to h1-h6, clamped', function()
    assert.is_true(vim.tbl_contains(render({ '* One' }), '<h1>One</h1>'))
    assert.is_true(vim.tbl_contains(render({ '******* Deep' }), '<h6>Deep</h6>'))
  end)

  it('escapes special characters in text', function()
    assert.is_true(vim.tbl_contains(render({ 'a < b & c > d' }), '<p>a &lt; b &amp; c &gt; d</p>'))
  end)

  it('renders bold as <b>', function()
    assert.is_true(vim.tbl_contains(render({ 'a *bold* word' }), '<p>a <b>bold</b> word</p>'))
  end)

  it('renders a link with escaped href/description', function()
    assert.is_true(
      vim.tbl_contains(render({ 'see [[https://x.com][A & B]] now' }), '<p>see <a href="https://x.com">A &amp; B</a> now</p>')
    )
  end)

  it('renders a src block with a language class', function()
    local text = joined({ '#+begin_src lua', 'print(1)', '#+end_src' })
    assert.is_not_nil(text:find('<pre><code class="language-lua">print(1)</code></pre>', 1, true))
  end)

  it('renders babel results in their own <pre> right after the code', function()
    local doc = { footnotes = {}, options = {}, blocks = { { type = 'src', lang = 'lua', body = { 'print(1)' }, results = { '1' }, show_code = true } } }
    local out = table.concat(html.render(doc), '\n')
    assert.is_not_nil(out:find('<pre><code class="language-lua">print(1)</code></pre>', 1, true))
    assert.is_not_nil(out:find('<pre class="results">1</pre>', 1, true))
  end)

  it('omits the code <pre> when show_code is false (:exports results)', function()
    local doc = { footnotes = {}, options = {}, blocks = { { type = 'src', lang = 'lua', body = { 'print(1)' }, results = { '1' }, show_code = false } } }
    local out = table.concat(html.render(doc), '\n')
    assert.is_nil(out:find('<code', 1, true))
    assert.is_not_nil(out:find('<pre class="results">1</pre>', 1, true))
  end)

  it('renders a flat unordered list', function()
    local out = render({ '- a', '- b' })
    assert.are.same({ '<ul>', '<li>a</li>', '<li>b</li></ul>' }, out)
  end)

  it('renders a flat ordered list with <ol>', function()
    local out = render({ '1. a', '1. b' })
    assert.are.same({ '<ol>', '<li>a</li>', '<li>b</li></ol>' }, out)
  end)

  it('nests a sub-list inside its parent <li>', function()
    local out = render({ '- top', '  - nested' })
    assert.are.same({ '<ul>', '<li>top', '<ul>', '<li>nested</li></ul></li></ul>' }, out)
  end)

  it('renders a checkbox item as a disabled input', function()
    local out = render({ '- [X] done' })
    assert.is_true(vim.tbl_contains(out, '<li><input type="checkbox" disabled checked> done</li></ul>'))
    local out2 = render({ '- [ ] todo' })
    assert.is_true(vim.tbl_contains(out2, '<li><input type="checkbox" disabled> todo</li></ul>'))
  end)

  it('renders a quote block as a blockquote', function()
    local out = render({ '#+BEGIN_QUOTE', 'wise words', '#+END_QUOTE' })
    assert.are.same({ '<blockquote>', '<p>wise words</p>', '</blockquote>' }, out)
  end)

  it('renders a footnote reference and definition', function()
    local text = joined({ 'note[fn:a]', '[fn:a] the text' })
    assert.is_not_nil(text:find('<sup id="fnref-a"><a href="#fn-a">a</a></sup>', 1, true))
    assert.is_not_nil(text:find('<p id="fn-a">a. the text</p>', 1, true))
  end)

  it('renders a title as h1 with author/date paragraphs', function()
    local out = render({ '#+TITLE: Doc', '#+AUTHOR: Jordan' })
    assert.are.equal('<h1>Doc</h1>', out[1])
    assert.is_true(vim.tbl_contains(out, '<p class="author">Jordan</p>'))
  end)

  it('includes a table of contents by default', function()
    local text = joined({ '* One' })
    assert.is_not_nil(text:find('<div id="toc">', 1, true))
  end)

  it('omits the table of contents when toc:nil', function()
    local text = joined({ '#+OPTIONS: toc:nil', '* One' })
    assert.is_nil(text:find('<div id="toc">', 1, true))
  end)

  it('closes every opened <ul> at the end of the document', function()
    local text = joined({ '- a', '  - b' })
    local _, opens = text:gsub('<ul>', '')
    local _, closes = text:gsub('</ul>', '')
    assert.are.equal(2, opens)
    assert.are.equal(opens, closes)
  end)
end)

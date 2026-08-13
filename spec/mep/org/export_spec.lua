local export = require('mep.org.export')

local TODO = { 'TODO', 'DONE' }

local function parse(lines, opts)
  opts = opts or {}
  opts.todo_keywords = opts.todo_keywords or TODO
  return export.parse_lines(lines, opts)
end

describe('mep.org.export', function()
  describe('parse_lines: document metadata', function()
    it('reads #+TITLE:/#+AUTHOR:/#+DATE:', function()
      local doc = parse({ '#+TITLE: My Doc', '#+AUTHOR: Jordan', '#+DATE: 2026-08-11' })
      assert.are.equal('My Doc', doc.title)
      assert.are.equal('Jordan', doc.author)
      assert.are.equal('2026-08-11', doc.date)
    end)

    it('parses #+OPTIONS: into a key/value table', function()
      local doc = parse({ '#+OPTIONS: toc:nil num:t' })
      assert.are.equal('nil', doc.options.toc)
      assert.are.equal('t', doc.options.num)
    end)

    it('is nil/empty when the doc has no keyword lines', function()
      local doc = parse({ '* Just a headline' })
      assert.is_nil(doc.title)
      assert.is_nil(doc.author)
    end)
  end)

  describe('truthy_option', function()
    it('defaults when the option is absent', function()
      local doc = parse({})
      assert.is_true(export.truthy_option(doc, 'num', true))
      assert.is_false(export.truthy_option(doc, 'num', false))
    end)

    it('treats "nil" and "no" as false regardless of default', function()
      local doc = parse({ '#+OPTIONS: toc:nil' })
      assert.is_false(export.truthy_option(doc, 'toc', true))
    end)

    it('treats any other value as true', function()
      local doc = parse({ '#+OPTIONS: toc:t' })
      assert.is_true(export.truthy_option(doc, 'toc', false))
    end)
  end)

  describe('parse_lines: headlines', function()
    it('produces a headline block per headline, with todo/priority/tags', function()
      local doc = parse({ '* TODO [#A] Buy milk :errand:' })
      assert.are.equal(1, #doc.blocks)
      local b = doc.blocks[1]
      assert.are.equal('headline', b.type)
      assert.are.equal(1, b.level)
      assert.are.equal('TODO', b.todo)
      assert.are.equal('A', b.priority)
      assert.are.equal('Buy milk', b.title)
      assert.are.same({ 'errand' }, b.tags)
    end)

    it('numbers headlines by default (num:t)', function()
      local doc = parse({ '* One', '** Sub', '* Two' })
      assert.are.equal('1', doc.blocks[1].number)
      assert.are.equal('1.1', doc.blocks[2].number)
      assert.are.equal('2', doc.blocks[3].number)
    end)

    it('does not number headlines when #+OPTIONS: num:nil', function()
      local doc = parse({ '#+OPTIONS: num:nil', '* One' })
      assert.is_nil(doc.blocks[1].number)
    end)

    it('skips a :noexport: headline and its whole subtree', function()
      local doc = parse({ '* Visible', '* Hidden :noexport:', 'body text', '** Hidden child', '* After' })
      local titles = {}
      for _, b in ipairs(doc.blocks) do
        if b.type == 'headline' then
          titles[#titles + 1] = b.title
        end
      end
      assert.are.same({ 'Visible', 'After' }, titles)
    end)
  end)

  describe('parse_lines: paragraphs', function()
    it('groups contiguous non-blank lines into one paragraph', function()
      local doc = parse({ 'line one', 'line two', '', 'line three' })
      assert.are.equal(2, #doc.blocks)
      assert.are.same({ 'line one', 'line two' }, doc.blocks[1].lines)
      assert.are.same({ 'line three' }, doc.blocks[2].lines)
    end)

    it('macro-expands paragraph text', function()
      local doc = parse({ '#+MACRO: who World', 'Hello {{{who}}}!' })
      assert.are.same({ 'Hello World!' }, doc.blocks[1].lines)
    end)
  end)

  describe('parse_lines: lists', function()
    it('flattens a simple bullet list with depth 0', function()
      local doc = parse({ '- one', '- two' })
      assert.are.equal(2, #doc.blocks)
      assert.are.equal('list_item', doc.blocks[1].type)
      assert.are.equal(0, doc.blocks[1].depth)
      assert.are.equal('one', doc.blocks[1].text)
    end)

    it('derives nesting depth from indentation', function()
      local doc = parse({ '- top', '  - nested', '    - deeper', '- back to top' })
      assert.are.equal(0, doc.blocks[1].depth)
      assert.are.equal(1, doc.blocks[2].depth)
      assert.are.equal(2, doc.blocks[3].depth)
      assert.are.equal(0, doc.blocks[4].depth)
    end)

    it('marks ordered items and checkbox state', function()
      local doc = parse({ '1. first', '- [ ] todo', '- [X] done' })
      assert.is_true(doc.blocks[1].ordered)
      assert.is_false(doc.blocks[2].checkbox)
      assert.is_true(doc.blocks[3].checkbox)
    end)

    it('folds a more-indented continuation line into the preceding item', function()
      local doc = parse({ '- item', '  more text' })
      assert.are.equal(1, #doc.blocks)
      assert.are.equal('item more text', doc.blocks[1].text)
    end)
  end)

  describe('parse_lines: src and special blocks', function()
    it('produces a src block with lang + body', function()
      local doc = parse({ '#+begin_src lua', 'print(1)', '#+end_src' })
      assert.are.equal('src', doc.blocks[1].type)
      assert.are.equal('lua', doc.blocks[1].lang)
      assert.are.same({ 'print(1)' }, doc.blocks[1].body)
    end)

    it('produces a quote block', function()
      local doc = parse({ '#+BEGIN_QUOTE', 'to be', '#+END_QUOTE' })
      assert.are.equal('block', doc.blocks[1].type)
      assert.are.equal('quote', doc.blocks[1].kind)
      assert.are.same({ 'to be' }, doc.blocks[1].body)
    end)

    it('macro-expands quote/verse/center bodies but not example/src', function()
      local doc = parse({
        '#+MACRO: x expanded',
        '#+BEGIN_QUOTE',
        '{{{x}}}',
        '#+END_QUOTE',
        '#+BEGIN_EXAMPLE',
        '{{{x}}}',
        '#+END_EXAMPLE',
      })
      assert.are.same({ 'expanded' }, doc.blocks[1].body)
      assert.are.same({ '{{{x}}}' }, doc.blocks[2].body)
    end)

    it('drops a comment block entirely', function()
      local doc = parse({ 'before', '#+BEGIN_COMMENT', 'secret', '#+END_COMMENT', 'after' })
      assert.are.equal(2, #doc.blocks)
    end)
  end)

  describe('parse_lines: skipped structural lines', function()
    it('skips planning lines, property drawers, and comments', function()
      local doc = parse({
        '* Task',
        'SCHEDULED: <2026-08-11 Tue>',
        ':PROPERTIES:',
        ':ID: abc',
        ':END:',
        '# just a comment',
        'body text',
      })
      assert.are.equal(2, #doc.blocks)
      assert.are.equal('headline', doc.blocks[1].type)
      assert.are.equal('paragraph', doc.blocks[2].type)
      assert.are.same({ 'body text' }, doc.blocks[2].lines)
    end)

    it('skips a :LOGBOOK: drawer', function()
      local doc = parse({ '* Task', ':LOGBOOK:', 'CLOCK: [2026-08-11 Tue 09:00]--[2026-08-11 Tue 10:00]', ':END:', 'body' })
      assert.are.equal(2, #doc.blocks)
      assert.are.equal('paragraph', doc.blocks[2].type)
    end)
  end)

  describe('parse_lines: footnotes', function()
    it('collects standalone definitions without emitting them as blocks', function()
      local doc = parse({ 'see [fn:a]', '[fn:a] the definition' })
      assert.are.equal(1, #doc.blocks)
      assert.are.equal(1, #doc.footnotes)
      assert.are.equal('a', doc.footnotes[1].name)
      assert.are.equal('the definition', doc.footnotes[1].text)
    end)

    it('only records the first definition of a given name', function()
      local doc = parse({ '[fn:a] first', '[fn:a] second' })
      assert.are.equal(1, #doc.footnotes)
      assert.are.equal('first', doc.footnotes[1].text)
    end)
  end)

  describe('parse / parse_lines: includes', function()
    it('parse resolves #+INCLUDE: by default', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ 'included text' }, dir .. '/child.org')
      local bufpath = dir .. '/main.org'
      vim.fn.writefile({ '#+INCLUDE: "child.org"' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)

      local doc = export.parse(buf, { todo_keywords = TODO })
      assert.are.same({ 'included text' }, doc.blocks[1].lines)
      vim.fn.delete(dir, 'rf')
    end)
  end)

  describe('tokenize_inline', function()
    it('tokenizes plain text with no markup as a single text token', function()
      local tokens = export.tokenize_inline('just plain text')
      assert.are.equal(1, #tokens)
      assert.are.equal('text', tokens[1].type)
      assert.are.equal('just plain text', tokens[1].text)
    end)

    it('tokenizes bold text', function()
      local tokens = export.tokenize_inline('a *bold* word')
      assert.are.equal(3, #tokens)
      assert.are.equal('text', tokens[1].type)
      assert.are.equal('bold', tokens[2].type)
      assert.are.equal('bold', tokens[2].text)
      assert.are.equal('text', tokens[3].type)
    end)

    it('tokenizes italic, underline, strike, code, verbatim', function()
      local cases = {
        { '/it/', 'italic' },
        { '_u_', 'underline' },
        { '+s+', 'strike' },
        { '~c~', 'code' },
        { '=v=', 'verbatim' },
      }
      for _, case in ipairs(cases) do
        local tokens = export.tokenize_inline(case[1])
        assert.are.equal(1, #tokens)
        assert.are.equal(case[2], tokens[1].type)
      end
    end)

    it('does not treat "5 * 3 = 15" as bold', function()
      local tokens = export.tokenize_inline('5 * 3 = 15')
      for _, t in ipairs(tokens) do
        assert.are.equal('text', t.type)
      end
    end)

    it('tokenizes a link with description', function()
      local tokens = export.tokenize_inline('see [[https://x.com][X]] now')
      assert.are.equal(3, #tokens)
      assert.are.equal('link', tokens[2].type)
      assert.are.equal('https://x.com', tokens[2].target)
      assert.are.equal('X', tokens[2].description)
    end)

    it('tokenizes a bare link', function()
      local tokens = export.tokenize_inline('[[https://x.com]]')
      assert.are.equal(1, #tokens)
      assert.are.equal('link', tokens[1].type)
      assert.is_nil(tokens[1].description)
    end)

    it('tokenizes a footnote reference', function()
      local tokens = export.tokenize_inline('word[fn:a] rest')
      assert.are.equal(3, #tokens)
      assert.are.equal('footnote', tokens[2].type)
      assert.are.equal('a', tokens[2].name)
      assert.is_nil(tokens[2].def)
    end)

    it('tokenizes an anonymous inline footnote definition', function()
      local tokens = export.tokenize_inline('word[fn::inline def] rest')
      assert.are.equal('footnote', tokens[2].type)
      assert.is_nil(tokens[2].name)
      assert.are.equal('inline def', tokens[2].def)
    end)

    it('handles multiple markers in one string in order', function()
      local tokens = export.tokenize_inline('*a* and /b/')
      local types = {}
      for _, t in ipairs(tokens) do
        types[#types + 1] = t.type
      end
      assert.are.same({ 'bold', 'text', 'italic' }, types)
    end)
  end)

  describe('render', function()
    it('dispatches to the named backend', function()
      local doc = parse({ '* Title' })
      local out = export.render(doc, 'markdown')
      assert.is_true(vim.tbl_contains(out, '# Title'))
    end)

    it('errors on an unknown backend', function()
      assert.has_error(function()
        export.render(parse({}), 'nope')
      end)
    end)
  end)

  describe('default_path', function()
    it('derives a path from the buffer name with the backend extension', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, '/tmp/notes.org')
      assert.are.equal('/tmp/notes.md', export.default_path(buf, 'markdown'))
      assert.are.equal('/tmp/notes.txt', export.default_path(buf, 'ascii'))
      assert.are.equal('/tmp/notes.html', export.default_path(buf, 'html'))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it('returns nil for an unsaved buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_nil(export.default_path(buf, 'markdown'))
    end)
  end)

  describe('export_to_file', function()
    it('writes the rendered document to disk', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/doc.org'
      vim.fn.writefile({ '* Title', 'body text' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)

      local path = export.export_to_file(buf, 'markdown', nil, { todo_keywords = TODO })
      assert.are.equal(dir .. '/doc.md', path)
      local written = vim.fn.readfile(path)
      assert.is_true(vim.tbl_contains(written, '# Title'))
      assert.is_true(vim.tbl_contains(written, 'body text'))
      vim.fn.delete(dir, 'rf')
    end)
  end)

  describe('export_subtree', function()
    it('exports only the subtree, renormalizing child levels and using the headline as title', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/doc.org'
      vim.fn.writefile({ '* Intro', 'skip me', '* Chapter One', '** Section', 'chapter body', '* Outro' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)

      local path = export.export_subtree(buf, 3, 'markdown', nil, { todo_keywords = TODO })
      local written = vim.fn.readfile(path)
      assert.are.equal('# Chapter One', written[1])
      assert.is_true(vim.tbl_contains(written, '# Section'))
      assert.is_true(vim.tbl_contains(written, 'chapter body'))
      assert.is_false(vim.tbl_contains(written, 'skip me'))
      vim.fn.delete(dir, 'rf')
    end)

    it('prefers an :EXPORT_TITLE: property over the headline title', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/doc.org'
      vim.fn.writefile({ '* Chapter One', ':PROPERTIES:', ':EXPORT_TITLE: Custom Title', ':END:', 'body' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)

      local path = export.export_subtree(buf, 1, 'markdown', nil, { todo_keywords = TODO })
      local written = vim.fn.readfile(path)
      assert.are.equal('# Custom Title', written[1])
      vim.fn.delete(dir, 'rf')
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, '/tmp/noheadline.org')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'no headline here' })
      assert.is_nil(export.export_subtree(buf, 1, 'markdown', nil, { todo_keywords = TODO }))
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)
  end)

  describe('dispatch_interactive', function()
    it('exports via the chosen backend to the default path', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local bufpath = dir .. '/doc.org'
      vim.fn.writefile({ '* Title' }, bufpath)
      local buf = vim.fn.bufadd(bufpath)
      vim.fn.bufload(buf)

      local orig_select = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb('html')
      end
      export.dispatch_interactive(buf, { todo_keywords = TODO })
      vim.ui.select = orig_select

      assert.are.equal(1, vim.fn.filereadable(dir .. '/doc.html'))
      vim.fn.delete(dir, 'rf')
    end)
  end)
end)

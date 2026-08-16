local parser = require('mep.bib.parser')

describe('mep.bib.parser', function()
  it('parses a single entry with braced field values', function()
    local text = [[
@article{smith2020,
  title = {A Great Paper},
  author = {Smith, John},
  year = {2020},
}
]]
    local entries = parser.parse(text)
    assert.are.equal(1, #entries)
    assert.are.equal('smith2020', entries[1].key)
    assert.are.equal('article', entries[1].type)
    assert.are.equal('A Great Paper', entries[1].fields.title)
    assert.are.equal('Smith, John', entries[1].fields.author)
    assert.are.equal('2020', entries[1].fields.year)
  end)

  it('parses double-quoted field values', function()
    local text = '@book{doe2019, title = "A Fine Book", author = "Doe, Jane"}'
    local entries = parser.parse(text)
    assert.are.equal('A Fine Book', entries[1].fields.title)
    assert.are.equal('Doe, Jane', entries[1].fields.author)
  end)

  it('parses a bare (unquoted) field value', function()
    local text = '@article{x2021, year = 2021}'
    local entries = parser.parse(text)
    assert.are.equal('2021', entries[1].fields.year)
  end)

  it('does not split on a comma inside a braced value', function()
    local text = '@article{x, title = {Some, Title, With Commas}, year = {2022}}'
    local entries = parser.parse(text)
    assert.are.equal('Some, Title, With Commas', entries[1].fields.title)
    assert.are.equal('2022', entries[1].fields.year)
  end)

  it('handles a nested-braced value (a real BibTeX title-casing convention)', function()
    local text = '@article{x, title = {Some {Nested} Title}}'
    local entries = parser.parse(text)
    assert.are.equal('Some {Nested} Title', entries[1].fields.title)
  end)

  it('parses multiple entries in one file', function()
    local text = table.concat({
      '@article{a1, title = {First}}',
      '@book{b1, title = {Second}}',
    }, '\n')
    local entries = parser.parse(text)
    assert.are.equal(2, #entries)
    assert.are.equal('a1', entries[1].key)
    assert.are.equal('b1', entries[2].key)
  end)

  it('lowercases field names', function()
    local text = '@article{x, TITLE = {Upper}, Author = {A}}'
    local entries = parser.parse(text)
    assert.are.equal('Upper', entries[1].fields.title)
    assert.are.equal('A', entries[1].fields.author)
  end)

  it('lowercases the entry type', function()
    local text = '@ARTICLE{x, title = {T}}'
    local entries = parser.parse(text)
    assert.are.equal('article', entries[1].type)
  end)

  it('returns an empty list for text with no entries', function()
    assert.are.same({}, parser.parse('not a bibtex file'))
  end)

  it('accepts a hyphenated field name', function()
    local text = '@article{x, url-date = {2023-01-01}}'
    local entries = parser.parse(text)
    assert.are.equal('2023-01-01', entries[1].fields['url-date'])
  end)
end)

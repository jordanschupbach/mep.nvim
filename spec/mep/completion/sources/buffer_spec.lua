local buffer_source = require('mep.completion.sources.buffer')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function ctx(bufnr, prefix)
  return { bufnr = bufnr, prefix = prefix }
end

describe('mep.completion.sources.buffer', function()
  it('returns matching words longer than the prefix', function()
    local buf = make_buf({ 'local foobar = 1', 'local foobaz = 2' })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    local words = {}
    for _, it in ipairs(result) do
      words[#words + 1] = it.word
    end
    table.sort(words)
    assert.are.same({ 'foobar', 'foobaz' }, words)
  end)

  it('excludes a word exactly equal to the prefix (nothing extra to complete)', function()
    local buf = make_buf({ 'foo foobar' })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    assert.are.equal(1, #result)
    assert.are.equal('foobar', result[1].word)
  end)

  it('deduplicates repeated words', function()
    local buf = make_buf({ 'foobar foobar foobar' })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    assert.are.equal(1, #result)
  end)

  it('returns nothing for an empty prefix', function()
    local buf = make_buf({ 'foobar' })
    local result
    buffer_source.complete(ctx(buf, ''), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)

  it('tags each item as a Buffer-kind item', function()
    local buf = make_buf({ 'foobar' })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    assert.are.equal('Buffer', result[1].kind)
    assert.are.equal('[Buffer]', result[1].menu)
  end)

  it('is case-sensitive', function()
    local buf = make_buf({ 'FooBar' })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)

  it('returns nothing for an invalid buffer', function()
    local buf = make_buf({ 'foobar' })
    vim.api.nvim_buf_delete(buf, { force = true })
    local result
    buffer_source.complete(ctx(buf, 'foo'), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)
end)

local linkconceal = require('mep.markdown.linkconceal')

local ns = vim.api.nvim_create_namespace('mep_markdown_conceal')

local function concealed_spans(bufnr, lnum)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { lnum - 1, 0 }, { lnum - 1, -1 }, { details = true })
  local spans = {}
  for _, m in ipairs(marks) do
    spans[#spans + 1] = { m[3], m[4].end_col }
  end
  table.sort(spans, function(a, b)
    return a[1] < b[1]
  end)
  return spans
end

describe('mep.markdown.linkconceal', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe('apply — links', function()
    it('conceals the brackets/url of [text](url), leaving text visible', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'See [a link](https://x.com) here.' })
      linkconceal.apply(bufnr)
      local spans = concealed_spans(bufnr, 1)
      assert.are.equal(2, #spans)
      -- span 1: '[' at col 4 (0-indexed)
      assert.are.same({ 4, 5 }, spans[1])
      -- span 2: '](https://x.com)' right after 'a link'
      assert.are.same({ 11, 27 }, spans[2])
    end)

    it('handles multiple links on one line', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '[one](a) and [two](b)' })
      linkconceal.apply(bufnr)
      assert.are.equal(4, #concealed_spans(bufnr, 1))
    end)
  end)

  describe('apply — emphasis', function()
    it('conceals ** markers around bold text', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'This is **bold** text.' })
      linkconceal.apply(bufnr)
      local spans = concealed_spans(bufnr, 1)
      assert.are.equal(2, #spans)
      assert.are.same({ 8, 10 }, spans[1]) -- '**' at cols 8-9 (0-indexed)
      assert.are.same({ 14, 16 }, spans[2]) -- '**' at cols 14-15
    end)

    it('conceals single * markers around italic text', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'This is *italic* text.' })
      linkconceal.apply(bufnr)
      assert.are.equal(2, #concealed_spans(bufnr, 1))
    end)

    it('conceals __ and _ the same way as ** and *', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '__bold__ and _italic_' })
      linkconceal.apply(bufnr)
      assert.are.equal(4, #concealed_spans(bufnr, 1))
    end)

    it('conceals ~~ strikethrough markers', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '~~gone~~' })
      linkconceal.apply(bufnr)
      assert.are.equal(2, #concealed_spans(bufnr, 1))
    end)

    it('does not treat a bare "**" with no closer as emphasis', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'just ** two stars' })
      linkconceal.apply(bufnr)
      assert.are.same({}, concealed_spans(bufnr, 1))
    end)

    it('does not match "**" as two separate italics (whitespace-flanking rule)', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '5 * 3 * 2' })
      linkconceal.apply(bufnr)
      assert.are.same({}, concealed_spans(bufnr, 1))
    end)

    it('correctly picks the double-star span over a false single-star reading', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '**bold** and *italic*.' })
      linkconceal.apply(bufnr)
      local spans = concealed_spans(bufnr, 1)
      -- 2 spans for **bold** + 2 for *italic* = 4 total, not garbled by
      -- the single-star matcher misfiring on the double-star run.
      assert.are.equal(4, #spans)
      assert.are.same({ 0, 2 }, spans[1])
      assert.are.same({ 6, 8 }, spans[2])
    end)
  end)

  describe('clear', function()
    it('removes every concealment extmark', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '**bold**' })
      linkconceal.apply(bufnr)
      linkconceal.clear(bufnr)
      assert.are.same({}, concealed_spans(bufnr, 1))
    end)
  end)
end)

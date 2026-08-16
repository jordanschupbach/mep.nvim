local body = require('mep.flashcards.body')

describe('mep.flashcards.body', function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = 'org'
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('returns the plain body text under a headline', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q: capital of France?', 'Paris.' })
    assert.are.same({ 'Paris.' }, body.answer_text(bufnr, 1))
  end)

  it('trims leading/trailing blank lines', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q', '', '', 'Answer text.', '', '' })
    assert.are.same({ 'Answer text.' }, body.answer_text(bufnr, 1))
  end)

  it('stops at the next headline of any level (excludes child subtrees)', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q', 'own body', '** Child', 'child body' })
    assert.are.same({ 'own body' }, body.answer_text(bufnr, 1))
  end)

  it('skips a planning line', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q', 'SCHEDULED: <2024-01-01 Mon>', 'The answer.' })
    assert.are.same({ 'The answer.' }, body.answer_text(bufnr, 1))
  end)

  it('skips a properties drawer', function()
    vim.api.nvim_buf_set_lines(
      bufnr,
      0,
      -1,
      false,
      { '* Q', ':PROPERTIES:', ':DRILL_EF: 2.5', ':END:', 'The answer.' }
    )
    assert.are.same({ 'The answer.' }, body.answer_text(bufnr, 1))
  end)

  it('skips both a planning line and a properties drawer, in order', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '* Q',
      'SCHEDULED: <2024-01-01 Mon>',
      ':PROPERTIES:',
      ':DRILL_EF: 2.5',
      ':END:',
      'The answer.',
    })
    assert.are.same({ 'The answer.' }, body.answer_text(bufnr, 1))
  end)

  it('returns {} for a headline with no body at all', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q', '* Next' })
    assert.are.same({}, body.answer_text(bufnr, 1))
  end)

  it('returns {} for a headline that is the last line in the buffer', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q' })
    assert.are.same({}, body.answer_text(bufnr, 1))
  end)

  it('preserves multiple body lines and internal blank lines', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* Q', 'line one', '', 'line two' })
    assert.are.same({ 'line one', '', 'line two' }, body.answer_text(bufnr, 1))
  end)
end)

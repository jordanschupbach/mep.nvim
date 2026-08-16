local resultshl = require('mep.org.resultshl')

local NS = vim.api.nvim_create_namespace('mep_org_results_block')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

local function rows(buf)
  local marks = extmarks(buf)
  local r = {}
  for _, m in ipairs(marks) do
    r[#r + 1] = m[2]
  end
  table.sort(r)
  return r
end

describe('mep.org.resultshl', function()
  describe('apply', function()
    it('covers a one-line result, including the #+RESULTS: line itself', function()
      local buf = make_buf({
        'before',
        '#+RESULTS:',
        ': 42',
        'after',
      })
      resultshl.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(2, #marks)
      assert.are.same({ 1, 2 }, rows(buf)) -- 0-indexed rows for lines 2-3

      for _, m in ipairs(marks) do
        assert.are.equal(resultshl.hl_group, m[4].hl_group)
        assert.is_true(m[4].hl_eol)
      end
    end)

    it('covers a multi-line #+begin_example ... #+end_example result, including delimiters', function()
      local buf = make_buf({
        '#+RESULTS:',
        '#+begin_example',
        'line one',
        'line two',
        '#+end_example',
        'after',
      })
      resultshl.apply(buf)
      assert.are.same({ 0, 1, 2, 3, 4 }, rows(buf))
    end)

    it('covers just the #+RESULTS: line for an empty result', function()
      local buf = make_buf({ '#+RESULTS:', 'after' })
      resultshl.apply(buf)
      assert.are.same({ 0 }, rows(buf))
    end)

    it('does not mark lines outside any results block', function()
      local buf = make_buf({ 'plain text', 'more plain text' })
      resultshl.apply(buf)
      assert.are.same({}, extmarks(buf))
    end)

    it('marks multiple results blocks independently', function()
      local buf = make_buf({
        '#+RESULTS:', ': a',
        'x',
        '#+RESULTS:', ': b',
      })
      resultshl.apply(buf)
      assert.are.equal(4, #extmarks(buf))
    end)

    it('clears previous marks before recomputing', function()
      local buf = make_buf({ '#+RESULTS:', ': a' })
      resultshl.apply(buf)
      resultshl.apply(buf)
      assert.are.equal(2, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes every mark this module set', function()
      local buf = make_buf({ '#+RESULTS:', ': a' })
      resultshl.apply(buf)
      resultshl.clear(buf)
      assert.are.same({}, extmarks(buf))
    end)
  end)

  describe('define_default_hl', function()
    it('links MepOrgResultsBlock to Constant', function()
      resultshl.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = resultshl.hl_group })
      assert.are.equal('Constant', hl.link)
    end)
  end)
end)

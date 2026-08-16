local todohl = require('mep.org.todohl')

local NS = vim.api.nvim_create_namespace('mep_org_todo')
local TODO_KEYWORDS = { 'TODO', 'DONE' }

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

describe('mep.org.todohl', function()
  describe('apply', function()
    it('colors the TODO keyword with its configured color', function()
      local buf = make_buf({ '* TODO Buy milk' })
      todohl.apply(buf, TODO_KEYWORDS, { TODO = 'DiagnosticError', DONE = 'DiagnosticOk' })
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(0, marks[1][2]) -- row
      assert.are.equal(2, marks[1][3]) -- start col, right after "* "
      assert.are.equal(6, marks[1][4].end_col) -- end col, right after "TODO"
      assert.are.equal('DiagnosticError', marks[1][4].hl_group)
    end)

    it('colors DONE differently from TODO', function()
      local buf = make_buf({ '* TODO one', '* DONE two' })
      todohl.apply(buf, TODO_KEYWORDS, { TODO = 'DiagnosticError', DONE = 'DiagnosticOk' })
      local marks = extmarks(buf)
      table.sort(marks, function(a, b)
        return a[2] < b[2]
      end)
      assert.are.equal('DiagnosticError', marks[1][4].hl_group)
      assert.are.equal('DiagnosticOk', marks[2][4].hl_group)
    end)

    it('falls back to hl_groups, cycling by position in todo_keywords, when a keyword has no configured color', function()
      local buf = make_buf({ '* WAITING blocked' })
      todohl.apply(buf, { 'TODO', 'WAITING', 'DONE' }, { TODO = 'DiagnosticError', DONE = 'DiagnosticOk' })
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(todohl.hl_groups[2], marks[1][4].hl_group) -- WAITING is index 2
    end)

    it('cycles hl_groups past its own fixed length', function()
      local keywords = {}
      for i = 1, #todohl.hl_groups + 1 do
        keywords[i] = 'STATE' .. i
      end
      local buf = make_buf({ '* ' .. keywords[#keywords] .. ' overflow' })
      todohl.apply(buf, keywords, {})
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(todohl.hl_groups[1], marks[1][4].hl_group)
    end)

    it('does not mark a headline with no TODO keyword', function()
      local buf = make_buf({ '* just a title' })
      todohl.apply(buf, TODO_KEYWORDS, {})
      assert.are.same({}, extmarks(buf))
    end)

    it('does not mark a title word that merely starts with a keyword', function()
      local buf = make_buf({ '* TODOs for later' })
      todohl.apply(buf, TODO_KEYWORDS, {})
      assert.are.same({}, extmarks(buf))
    end)

    it('does not mark non-headline lines', function()
      local buf = make_buf({ 'TODO not a headline' })
      todohl.apply(buf, TODO_KEYWORDS, {})
      assert.are.same({}, extmarks(buf))
    end)

    it('is a no-op with an empty todo_keywords list', function()
      local buf = make_buf({ '* TODO one' })
      todohl.apply(buf, {}, {})
      assert.are.same({}, extmarks(buf))
    end)

    it('clears previous marks before recomputing', function()
      local buf = make_buf({ '* TODO one' })
      todohl.apply(buf, TODO_KEYWORDS, {})
      todohl.apply(buf, TODO_KEYWORDS, {})
      assert.are.equal(1, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes every mark this module set', function()
      local buf = make_buf({ '* TODO one' })
      todohl.apply(buf, TODO_KEYWORDS, {})
      todohl.clear(buf)
      assert.are.same({}, extmarks(buf))
    end)
  end)

  describe('define_default_hl', function()
    it('links each MepOrgTodoKeywordN group to its configured target', function()
      todohl.define_default_hl()
      for i, group in ipairs(todohl.hl_groups) do
        local hl = vim.api.nvim_get_hl(0, { name = group })
        assert.are.equal(todohl.LINKS[i], hl.link)
      end
    end)

    it('picks red for the first fallback slot, matching real org-mode TODO', function()
      todohl.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = todohl.hl_groups[1] })
      assert.are.equal('DiagnosticError', hl.link)
    end)
  end)
end)

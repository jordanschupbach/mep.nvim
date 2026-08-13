local footnote = require('mep.org.footnote')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.footnote', function()
  describe('find', function()
    it('finds a plain reference', function()
      local s, e, name, def = footnote.find('see[fn:abc] here')
      assert.are.equal(4, s)
      assert.are.equal(11, e)
      assert.are.equal('abc', name)
      assert.is_nil(def)
    end)

    it('finds a named inline definition', function()
      local _, _, name, def = footnote.find('a [fn:abc:the definition] b')
      assert.are.equal('abc', name)
      assert.are.equal('the definition', def)
    end)

    it('finds an anonymous inline definition', function()
      local _, _, name, def = footnote.find('a [fn::anon def] b')
      assert.is_nil(name)
      assert.are.equal('anon def', def)
    end)

    it('returns nil when there is none', function()
      assert.is_nil(footnote.find('plain text'))
    end)
  end)

  describe('find_definitions', function()
    it('finds column-0 definition lines only', function()
      local lines = { '[fn:a] first def', 'body [fn:a] ref', '[fn:b] second def' }
      local defs = footnote.find_definitions(lines)
      assert.are.equal(2, #defs)
      assert.are.equal('a', defs[1].name)
      assert.are.equal('first def', defs[1].text)
      assert.are.equal(3, defs[2].lnum)
    end)

    it('ignores an indented [fn:name] line (not column 0)', function()
      assert.are.same({}, footnote.find_definitions({ '  [fn:a] not a def' }))
    end)
  end)

  describe('find_definition / find_reference', function()
    it('locates a definition by name', function()
      local buf = make_buf({ 'body [fn:a]', '[fn:a] def text' })
      assert.are.equal(2, footnote.find_definition(buf, 'a'))
    end)

    it('locates the first reference by name', function()
      local buf = make_buf({ 'first', 'body [fn:a] more', '[fn:a] def text' })
      assert.are.equal(2, footnote.find_reference(buf, 'a'))
    end)

    it('returns nil when absent', function()
      local buf = make_buf({ 'nothing here' })
      assert.is_nil(footnote.find_definition(buf, 'a'))
      assert.is_nil(footnote.find_reference(buf, 'a'))
    end)
  end)

  describe('at_cursor', function()
    it('is true on a reference', function()
      local buf = make_buf({ 'body [fn:a] more' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      vim.api.nvim_win_set_cursor(win, { 1, 6 })
      assert.is_true(footnote.at_cursor(buf, win))
      vim.api.nvim_win_close(win, true)
    end)

    it('is true on a definition line', function()
      local buf = make_buf({ '[fn:a] def text' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      assert.is_true(footnote.at_cursor(buf, win))
      vim.api.nvim_win_close(win, true)
    end)

    it('is false elsewhere', function()
      local buf = make_buf({ 'plain text' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      assert.is_false(footnote.at_cursor(buf, win))
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('goto_counterpart', function()
    it('jumps from a reference to its definition', function()
      local buf = make_buf({ 'body [fn:a] more', '[fn:a] def text' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      vim.api.nvim_win_set_cursor(win, { 1, 6 })
      assert.is_true(footnote.goto_counterpart(buf, win))
      assert.are.equal(2, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)

    it('jumps from a definition back to its reference', function()
      local buf = make_buf({ 'body [fn:a] more', '[fn:a] def text' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      assert.is_true(footnote.goto_counterpart(buf, win))
      assert.are.equal(1, vim.api.nvim_win_get_cursor(win)[1])
      vim.api.nvim_win_close(win, true)
    end)

    it('returns false when the cursor is on neither', function()
      local buf = make_buf({ 'plain text' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      assert.is_false(footnote.goto_counterpart(buf, win))
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('insert_interactive', function()
    it('inserts a reference at the cursor and appends a definition', function()
      local buf = make_buf({ 'hello world' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      vim.api.nvim_win_set_cursor(win, { 1, 5 })

      local orig_input = vim.ui.input
      local responses = { 'note', 'a footnote' }
      local n = 0
      vim.ui.input = function(_, cb)
        n = n + 1
        cb(responses[n])
      end

      footnote.insert_interactive(buf, win)
      vim.ui.input = orig_input

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('hello[fn:note] world', lines[1])
      assert.are.equal('[fn:note] a footnote', lines[2])
      vim.api.nvim_win_close(win, true)
    end)

    it('auto-numbers when the name is left blank', function()
      local buf = make_buf({ 'xy', '[fn:1] existing' })
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 10, height = 5 })
      vim.api.nvim_win_set_cursor(win, { 1, 1 })

      local orig_input = vim.ui.input
      local responses = { '', 'second note' }
      local n = 0
      vim.ui.input = function(_, cb)
        n = n + 1
        cb(responses[n])
      end

      footnote.insert_interactive(buf, win)
      vim.ui.input = orig_input

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.equal('x[fn:2]y', lines[1])
      assert.are.equal('[fn:1] existing', lines[2])
      assert.are.equal('[fn:2] second note', lines[3])
      vim.api.nvim_win_close(win, true)
    end)
  end)
end)

local property = require('mep.org.property')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('mep.org.property', function()
  describe('find', function()
    it('finds the drawer right after a headline', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:', 'body' })
      local start, stop = property.find(buf, 1)
      assert.are.equal(2, start)
      assert.are.equal(4, stop)
    end)

    it('skips a planning line before the drawer', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', ':PROPERTIES:', ':ID: 1', ':END:' })
      local start = property.find(buf, 1)
      assert.are.equal(3, start)
    end)

    it('returns nil when there is no drawer', function()
      local buf = make_buf({ '* Task', 'body' })
      assert.is_nil(property.find(buf, 1))
    end)

    it('returns nil for an unterminated drawer', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1' })
      assert.is_nil(property.find(buf, 1))
    end)
  end)

  describe('parse', function()
    it('parses every key/value pair in order', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':CUSTOM_ID: foo', ':ID: bar', ':END:' })
      local list, by_key = property.parse(buf, 1)
      assert.are.same({ { key = 'CUSTOM_ID', value = 'foo' }, { key = 'ID', value = 'bar' } }, list)
      assert.are.equal('foo', by_key.CUSTOM_ID)
      assert.are.equal('bar', by_key.ID)
    end)

    it('returns {}, {} for a headline with no drawer', function()
      local buf = make_buf({ '* Task' })
      local list, by_key = property.parse(buf, 1)
      assert.are.same({}, list)
      assert.are.same({}, by_key)
    end)

    it('by_key is keyed uppercase regardless of original casing', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':Custom_Id: foo', ':END:' })
      local _, by_key = property.parse(buf, 1)
      assert.are.equal('foo', by_key.CUSTOM_ID)
    end)

    it('last entry wins for a duplicate key', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: first', ':ID: second', ':END:' })
      local _, by_key = property.parse(buf, 1)
      assert.are.equal('second', by_key.ID)
    end)
  end)

  describe('get', function()
    it('reads a property case-insensitively', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':CUSTOM_ID: foo', ':END:' })
      assert.are.equal('foo', property.get(buf, 1, 'custom_id'))
    end)

    it('operates on the enclosing headline, not just an exact headline line', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:', 'body' })
      assert.are.equal('1', property.get(buf, 5, 'ID'))
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(property.get(buf, 1, 'ID'))
    end)
  end)

  describe('find_by', function()
    it('finds the headline whose own property matches', function()
      local buf = make_buf({ '* A', ':PROPERTIES:', ':ID: a1', ':END:', '* B', ':PROPERTIES:', ':ID: b1', ':END:' })
      assert.are.equal(5, property.find_by(buf, 'ID', 'b1'))
    end)

    it('returns nil when nothing matches', function()
      local buf = make_buf({ '* A' })
      assert.is_nil(property.find_by(buf, 'ID', 'nope'))
    end)
  end)

  describe('write / set / remove', function()
    it('creates a drawer for a headline with none', function()
      local buf = make_buf({ '* Task', 'body' })
      property.set(buf, 1, 'ID', '123')
      assert.are.same({ '* Task', ':PROPERTIES:', ':ID: 123', ':END:', 'body' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('creates a drawer after an existing planning line', function()
      local buf = make_buf({ '* Task', 'SCHEDULED: <2024-01-01 Mon>' })
      property.set(buf, 1, 'ID', '123')
      assert.are.same({ '* Task', 'SCHEDULED: <2024-01-01 Mon>', ':PROPERTIES:', ':ID: 123', ':END:' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('updates an existing entry in place rather than duplicating it', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: old', ':END:' })
      property.set(buf, 1, 'ID', 'new')
      assert.are.same({ '* Task', ':PROPERTIES:', ':ID: new', ':END:' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('adds a new key alongside existing ones', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:' })
      property.set(buf, 1, 'CUSTOM_ID', 'cid')
      assert.are.same({ '* Task', ':PROPERTIES:', ':ID: 1', ':CUSTOM_ID: cid', ':END:' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('returns nil when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      assert.is_nil(property.set(buf, 1, 'ID', '1'))
    end)

    it('removes a key and deletes the drawer when nothing is left', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:', 'body' })
      local removed = property.remove(buf, 1, 'ID')
      assert.is_true(removed)
      assert.are.same({ '* Task', 'body' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('removes just one key, keeping the drawer if others remain', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':CUSTOM_ID: c', ':END:' })
      property.remove(buf, 1, 'ID')
      assert.are.same({ '* Task', ':PROPERTIES:', ':CUSTOM_ID: c', ':END:' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('returns false when the key was not present', function()
      local buf = make_buf({ '* Task', ':PROPERTIES:', ':ID: 1', ':END:' })
      assert.is_false(property.remove(buf, 1, 'CUSTOM_ID'))
    end)
  end)

  describe('set_interactive', function()
    local orig_input
    before_each(function()
      orig_input = vim.ui.input
    end)
    after_each(function()
      vim.ui.input = orig_input
    end)

    it('prompts for key then value and sets the property', function()
      local buf = make_buf({ '* Task' })
      local prompts = {}
      vim.ui.input = function(opts, on_confirm)
        prompts[#prompts + 1] = opts.prompt
        on_confirm(#prompts == 1 and 'Effort' or '1:00')
      end
      property.set_interactive(buf, 1)
      assert.are.equal('1:00', property.get(buf, 1, 'Effort'))
    end)

    it('does nothing when the key prompt is cancelled', function()
      local buf = make_buf({ '* Task' })
      vim.ui.input = function(_, on_confirm)
        on_confirm(nil)
      end
      property.set_interactive(buf, 1)
      assert.are.same({ '* Task' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it('does nothing when lnum is not inside a headline', function()
      local buf = make_buf({ 'no headline' })
      local called = false
      vim.ui.input = function()
        called = true
      end
      property.set_interactive(buf, 1)
      assert.is_false(called)
    end)
  end)
end)

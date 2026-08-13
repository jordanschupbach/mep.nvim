local todo = require('mep.activitybar.todo')
local config = require('mep.activitybar.config')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.activitybar.todo', function()
  local saved_config
  local tmpdir, path

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
    path = tmpdir .. '/todos.json'
    config.setup({ todo = { persist_path = path } })
    todo._reset()
  end)

  after_each(function()
    todo._reset()
    config.options = saved_config
    vim.fn.delete(tmpdir, 'rf')
  end)

  describe('load', function()
    it('is an empty list when the file does not exist yet', function()
      todo.load()
      assert.are.same({}, todo.items)
    end)

    it('loads previously saved items', function()
      vim.fn.writefile({ vim.fn.json_encode({ { id = 1, text = 'existing', done = false } }) }, path)
      todo.load()
      assert.are.equal(1, #todo.items)
      assert.are.equal('existing', todo.items[1].text)
    end)

    it('falls back to an empty list on unparseable content', function()
      vim.fn.writefile({ 'not json' }, path)
      todo.load()
      assert.are.same({}, todo.items)
    end)
  end)

  describe('add / toggle_done / clear_done', function()
    it('adds a not-done item and persists it', function()
      todo.add('write tests')
      assert.are.equal(1, #todo.items)
      assert.is_false(todo.items[1].done)

      todo._reset()
      todo.load()
      assert.are.equal('write tests', todo.items[1].text)
    end)

    it('ignores an empty/nil text', function()
      todo.add('')
      todo.add(nil)
      assert.are.same({}, todo.items)
    end)

    it('assigns increasing ids even after items are removed', function()
      todo.add('a')
      todo.add('b')
      todo.toggle_done(todo.items[1].id)
      todo.clear_done()
      todo.add('c')
      assert.are.equal(3, todo.items[#todo.items].id)
    end)

    it('toggle_done flips just the matching item', function()
      todo.add('a')
      todo.add('b')
      local id_a = todo.items[1].id
      todo.toggle_done(id_a)
      assert.is_true(todo.items[1].done)
      assert.is_false(todo.items[2].done)
    end)

    it('clear_done removes only done items', function()
      todo.add('a')
      todo.add('b')
      todo.toggle_done(todo.items[1].id)
      todo.clear_done()
      assert.are.equal(1, #todo.items)
      assert.are.equal('b', todo.items[1].text)
    end)
  end)

  describe('add_interactive', function()
    it('prompts and adds the entered text', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('from prompt')
      end
      todo.add_interactive()
      vim.ui.input = orig_input
      assert.are.equal('from prompt', todo.items[1].text)
    end)

    it('does not add on a cancelled (nil) prompt', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      todo.add_interactive()
      vim.ui.input = orig_input
      assert.are.same({}, todo.items)
    end)
  end)

  describe('sections', function()
    it('always includes an "Add todo..." widget first', function()
      local widgets = todo.sections()[1].widgets
      assert.are.equal('Add todo...', widgets[1].text)
    end)

    it('only shows "Clear done" once something is done', function()
      todo.add('a')
      assert.are.equal('a', todo.sections()[1].widgets[2].text)
      todo.toggle_done(todo.items[1].id)
      assert.are.equal('Clear done', todo.sections()[1].widgets[2].text)
    end)

    it('renders a checkbox icon reflecting done state', function()
      todo.add('a')
      local id = todo.items[1].id
      assert.are.equal('[ ]', todo.sections()[1].widgets[2].icon)
      todo.toggle_done(id)
      -- "Clear done" now also appears (widgets[2]), pushing the item to [3]
      assert.are.equal('[x]', todo.sections()[1].widgets[3].icon)
    end)
  end)

  describe('sidebar / toggle', function()
    after_each(function()
      pcall(function()
        todo.sidebar():close()
      end)
    end)

    it('activating a todo widget toggles it done, live', function()
      todo.add('finish the feature')
      todo.sidebar().opts.animate = false
      todo.toggle()
      vim.api.nvim_win_set_cursor(todo.sidebar().win, { 3, 0 })
      feed('<CR>')
      assert.is_true(todo.items[1].done)
    end)
  end)
end)

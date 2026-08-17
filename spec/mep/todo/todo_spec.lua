local todo = require('mep.todo')
local config = require('mep.todo.config')
local org_config = require('mep.org.config')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

describe('mep.todo', function()
  local saved_options, saved_org_options
  local tmpdir

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    saved_org_options = vim.deepcopy(org_config.options)
    org_config.options = vim.deepcopy(org_config.defaults)
    todo._reset()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
  end)

  after_each(function()
    todo._reset()
    config.options = saved_options
    org_config.options = saved_org_options
    vim.fn.delete(tmpdir, 'rf')
    for _, lhs in ipairs({ '<F8>' }) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    for _, lhs in ipairs(config.defaults.keymaps.toggle) do
      pcall(vim.keymap.del, 'n', lhs)
    end
  end)

  describe('entries', function()
    it('returns {} when the configured file does not exist', function()
      config.options.file = tmpdir .. '/nope.org'
      assert.are.same({}, todo.entries())
    end)

    it('collects every headline, todo or not', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ '* TODO Write docs', '* DONE Ship it', '* Just a note' }, path)
      config.options.file = path
      local entries = todo.entries()
      assert.are.equal(3, #entries)
      assert.are.equal('Write docs', entries[1].title)
      assert.are.equal('TODO', entries[1].todo)
      assert.are.equal('DONE', entries[2].todo)
      assert.is_nil(entries[3].todo)
    end)
  end)

  describe('sections', function()
    it('renders a [ ]/[x]-prefixed widget per headline, colored by todo state', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ '* TODO Write docs', '* DONE Ship it' }, path)
      config.options.file = path
      local sections = todo.sections()
      local widgets = sections[1].widgets
      assert.are.equal('[ ]', widgets[1].icon)
      assert.are.equal('Write docs', widgets[1].text)
      assert.are.equal('DiagnosticError', widgets[1].hl)
      assert.are.equal('[x]', widgets[2].icon)
      assert.are.equal('DiagnosticOk', widgets[2].hl)
    end)

    it("shows a distinct empty state when the file doesn't exist", function()
      config.options.file = tmpdir .. '/nope.org'
      local widgets = todo.sections()[1].widgets
      assert.are.equal(1, #widgets)
      assert.are.equal('TODO.org not found', widgets[1].text)
    end)

    it('shows a distinct empty state for a file with no headlines', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ 'just prose, no headline' }, path)
      config.options.file = path
      local widgets = todo.sections()[1].widgets
      assert.are.equal(1, #widgets)
      assert.are.equal('No todos found', widgets[1].text)
    end)
  end)

  describe('sidebar / toggle', function()
    it('toggle opens the panel with current entries rendered', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ '* TODO Write docs' }, path)
      config.options.file = path
      todo.sidebar().opts.animate = false
      todo.toggle()
      assert.is_true(todo.sidebar():is_open())
      local lines = vim.api.nvim_buf_get_lines(todo.sidebar().buf, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find('Write docs', 1, true) then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('activating a headline widget jumps to it and closes the panel', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ '* TODO Write docs', '* DONE Ship it' }, path)
      config.options.file = path
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(scratch)
      todo.sidebar().opts.animate = false
      todo.toggle()
      vim.api.nvim_win_set_cursor(todo.sidebar().win, { 2, 0 })
      feed('<CR>')
      assert.is_false(todo.sidebar():is_open())
      assert.are.equal(vim.fn.fnamemodify(path, ':p'), vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p'))
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  describe('setup', function()
    it('applies config', function()
      todo.setup({ file = 'notes.org' })
      assert.are.equal('notes.org', config.options.file)
    end)

    it('binds keymaps.toggle to open/close the panel', function()
      local path = tmpdir .. '/TODO.org'
      vim.fn.writefile({ '* TODO Write docs' }, path)
      todo.setup({ file = path, keymaps = { toggle = { '<F8>' } } })
      todo.sidebar().opts.animate = false
      feed('<F8>')
      assert.is_true(todo.sidebar():is_open())
      feed('<F8>')
      assert.is_false(todo.sidebar():is_open())
    end)
  end)
end)

-- mep.picker.sources.commands enumerates every user-defined Ex command in
-- the whole nvim instance (not just ones this spec creates), and busted
-- runs the full suite in one persistent process, so other specs' own
-- commands are typically still around here too. Assertions below look up
-- specific items by name rather than assuming an exact item count.
local commands = require('mep.picker.sources.commands')

local function find_item(items, name)
  for _, item in ipairs(items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

describe('mep.picker.sources.commands', function()
  local created_global, created_buffer_local

  before_each(function()
    created_global = {}
    created_buffer_local = {}
  end)

  after_each(function()
    for _, name in ipairs(created_global) do
      pcall(vim.api.nvim_del_user_command, name)
    end
    for _, entry in ipairs(created_buffer_local) do
      pcall(vim.api.nvim_buf_del_user_command, entry.bufnr, entry.name)
    end
  end)

  describe('collect', function()
    it('includes a global user command', function()
      vim.api.nvim_create_user_command('MepPickerSpecFoo', function() end, { desc = 'a test command' })
      created_global[#created_global + 1] = 'MepPickerSpecFoo'

      local item = find_item(commands.collect(vim.api.nvim_get_current_buf()), 'MepPickerSpecFoo')
      assert.is_not_nil(item)
      assert.are.equal('a test command', item.definition)
    end)

    it('includes a buffer-local command for the given buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_create_user_command(buf, 'MepPickerSpecBufLocal', function() end, {})
      created_buffer_local[#created_buffer_local + 1] = { bufnr = buf, name = 'MepPickerSpecBufLocal' }

      local item = find_item(commands.collect(buf), 'MepPickerSpecBufLocal')
      assert.is_not_nil(item)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('excludes a buffer-local command scoped to a different buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_create_user_command(buf, 'MepPickerSpecOtherBuf', function() end, {})
      created_buffer_local[#created_buffer_local + 1] = { bufnr = buf, name = 'MepPickerSpecOtherBuf' }

      local other_buf = vim.api.nvim_create_buf(false, true)
      assert.is_nil(find_item(commands.collect(other_buf), 'MepPickerSpecOtherBuf'))

      vim.api.nvim_buf_delete(buf, { force = true })
      vim.api.nvim_buf_delete(other_buf, { force = true })
    end)

    it('sorts commands by name', function()
      vim.api.nvim_create_user_command('MepPickerSpecZeta', function() end, {})
      vim.api.nvim_create_user_command('MepPickerSpecAlpha', function() end, {})
      created_global[#created_global + 1] = 'MepPickerSpecZeta'
      created_global[#created_global + 1] = 'MepPickerSpecAlpha'

      local names = {}
      for _, item in ipairs(commands.collect(vim.api.nvim_get_current_buf())) do
        names[#names + 1] = item.name
      end
      local sorted = vim.deepcopy(names)
      table.sort(sorted)
      assert.are.same(sorted, names)
    end)
  end)

  describe('display', function()
    it('renders a bare command with no nargs/description', function()
      assert.are.equal(':Foo', commands.display({ name = 'Foo', nargs = '0', definition = '' }))
    end)

    it('shows nargs when the command takes arguments', function()
      assert.are.equal(':Foo (nargs=1)', commands.display({ name = 'Foo', nargs = '1', definition = '' }))
    end)

    it('appends the description when present', function()
      assert.are.equal(
        ':Foo (nargs=?) — does a thing',
        commands.display({ name = 'Foo', nargs = '?', definition = 'does a thing' })
      )
    end)

    it('appends a description with no nargs shown for a zero-arg command', function()
      assert.are.equal(':Foo — does a thing', commands.display({ name = 'Foo', nargs = '0', definition = 'does a thing' }))
    end)
  end)

  describe('run', function()
    it('executes a zero-arg command immediately, without prompting', function()
      local ran = false
      vim.api.nvim_create_user_command('MepPickerSpecRun', function()
        ran = true
      end, {})
      created_global[#created_global + 1] = 'MepPickerSpecRun'

      local original_input = vim.ui.input
      local prompted = false
      vim.ui.input = function(_, cb)
        prompted = true
        cb('')
      end
      commands.run({ name = 'MepPickerSpecRun', nargs = '0' })
      vim.ui.input = original_input

      assert.is_true(ran)
      assert.is_false(prompted)
    end)

    it('prompts for argument text and passes it through for a command that takes args', function()
      local received
      vim.api.nvim_create_user_command('MepPickerSpecRunArgs', function(cmd_opts)
        received = cmd_opts.args
      end, { nargs = '*' })
      created_global[#created_global + 1] = 'MepPickerSpecRunArgs'

      local original_input = vim.ui.input
      vim.ui.input = function(prompt_opts, cb)
        assert.matches('MepPickerSpecRunArgs', prompt_opts.prompt)
        cb('hello world')
      end
      commands.run({ name = 'MepPickerSpecRunArgs', nargs = '*' })
      vim.ui.input = original_input

      assert.are.equal('hello world', received)
    end)

    it('runs nothing when the argument prompt is cancelled', function()
      local ran = false
      vim.api.nvim_create_user_command('MepPickerSpecRunCancel', function()
        ran = true
      end, { nargs = '*' })
      created_global[#created_global + 1] = 'MepPickerSpecRunCancel'

      local original_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end
      commands.run({ name = 'MepPickerSpecRunCancel', nargs = '*' })
      vim.ui.input = original_input

      assert.is_false(ran)
    end)
  end)

  describe('picker_opts', function()
    it('scopes buffer-local commands to opts.bufnr', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_create_user_command(buf, 'MepPickerSpecScoped', function() end, {})
      created_buffer_local[#created_buffer_local + 1] = { bufnr = buf, name = 'MepPickerSpecScoped' }

      local opts = commands.picker_opts({ bufnr = buf })
      assert.is_not_nil(find_item(opts.items, 'MepPickerSpecScoped'))
      assert.are.equal('Commands', opts.prompt_title)
      assert.is_function(opts.entry_to_string)
      assert.is_function(opts.on_select)
      assert.is_function(opts.preview)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

local whichkey = require('mep.whichkey.whichkey')
local config = require('mep.whichkey.config')

local function to_raw(human)
  return vim.api.nvim_replace_termcodes(human, true, true, true)
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function del(mode, lhs)
  pcall(vim.keymap.del, mode, lhs)
end

local function close_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

describe('mep.whichkey.whichkey', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_config
    close_floats()
    del('n', '<leader>ff')
    del('n', '<leader>fg')
    del('n', '<leader>x')
    del('n', '<leader>')
    del('n', ',')
  end)

  describe('execute', function()
    it('calls a callback mapping directly', function()
      local called = false
      whichkey.execute({ callback = function()
        called = true
      end })
      assert.is_true(called)
    end)

    it('feeds a string rhs mapping through nvim_feedkeys', function()
      local orig = vim.api.nvim_feedkeys
      local captured_keys, captured_mode
      vim.api.nvim_feedkeys = function(keys, mode)
        captured_keys, captured_mode = keys, mode
      end
      whichkey.execute({ rhs = 'ihello<Esc>', noremap = 1 })
      vim.api.nvim_feedkeys = orig
      assert.are.equal(vim.api.nvim_replace_termcodes('ihello<Esc>', true, false, true), captured_keys)
      assert.are.equal('ni', captured_mode)
    end)

    it('uses remap mode for a non-noremap rhs mapping', function()
      local orig = vim.api.nvim_feedkeys
      local captured_mode
      vim.api.nvim_feedkeys = function(_, mode)
        captured_mode = mode
      end
      whichkey.execute({ rhs = 'x', noremap = 0 })
      vim.api.nvim_feedkeys = orig
      assert.are.equal('mi', captured_mode)
    end)

    it('evaluates an expr callback and feeds its result', function()
      local orig = vim.api.nvim_feedkeys
      local captured_keys
      vim.api.nvim_feedkeys = function(keys)
        captured_keys = keys
      end
      whichkey.execute({ expr = 1, noremap = 1, callback = function()
        return 'zz'
      end })
      vim.api.nvim_feedkeys = orig
      assert.are.equal(vim.api.nvim_replace_termcodes('zz', true, false, true), captured_keys)
    end)
  end)

  describe('render_grid', function()
    local function groups_of(n)
      local groups = {}
      for i = 1, n do
        groups[i] = { key = tostring(i), desc = 'do ' .. i }
      end
      return groups
    end

    it('fits everything on one line when the width comfortably allows it', function()
      local lines = whichkey.render_grid(groups_of(3), 120)
      assert.are.equal(1, #lines)
      assert.matches('do 1', lines[1])
      assert.matches('do 2', lines[1])
      assert.matches('do 3', lines[1])
    end)

    it('wraps into multiple rows, column-major, when the width is tight', function()
      -- 5 entries, each padded to a 10-col-wide "N     do N" cell (13
      -- with inter-column spacing); a width of 26 fits exactly 2
      -- columns, forcing 3 rows (column-major: 1,2,3 down the first
      -- column, 4,5 down the second).
      local lines = whichkey.render_grid(groups_of(5), 26)
      assert.are.equal(3, #lines)
      assert.matches('^1     do 1', lines[1])
      assert.matches('4     do 4', lines[1])
      assert.matches('^2     do 2', lines[2])
      assert.matches('5     do 5', lines[2])
      assert.matches('^3     do 3', lines[3])
    end)

    it('always uses at least one column, even when narrower than one entry', function()
      local lines = whichkey.render_grid(groups_of(2), 1)
      assert.are.equal(2, #lines)
    end)
  end)

  describe('layout', function()
    after_each(function()
      config.options.position = saved_config.position
      config.options.border = saved_config.border
    end)

    local groups = { { key = 'f', desc = 'find files' }, { key = 'x', desc = 'do x' } }

    it('cursor position: a compact single column relative to the cursor', function()
      config.setup({ position = 'cursor' })
      local lines, win_opts = whichkey.layout(groups)
      assert.are.equal(2, #lines)
      assert.are.equal('cursor', win_opts.relative)
      assert.are.equal(1, win_opts.row)
      assert.are.equal(0, win_opts.col)
      assert.are.equal(#lines, win_opts.height)
    end)

    it('bottom position (default): full width, anchored above the command line', function()
      config.setup({ position = 'bottom', border = 'rounded' })
      local _, win_opts = whichkey.layout(groups)
      assert.are.equal('editor', win_opts.relative)
      assert.are.equal(0, win_opts.col)
      assert.are.equal(vim.o.columns - 2, win_opts.width)
      assert.are.equal(vim.o.lines - vim.o.cmdheight - win_opts.height - 2, win_opts.row)
    end)

    it('top position: same width, anchored at row 0', function()
      config.setup({ position = 'top', border = 'rounded' })
      local _, win_opts = whichkey.layout(groups)
      assert.are.equal(0, win_opts.row)
    end)

    it('border = "none" removes the 1-cell padding reserved on every side', function()
      config.setup({ position = 'bottom', border = 'none' })
      local _, win_opts = whichkey.layout(groups)
      assert.are.equal(vim.o.columns, win_opts.width)
      assert.are.equal(vim.o.lines - vim.o.cmdheight - win_opts.height, win_opts.row)
    end)

    it('never anchors above row 0 even with more groups than fit', function()
      config.setup({ position = 'bottom' })
      local many = {}
      for i = 1, 500 do
        many[i] = { key = tostring(i), desc = 'entry ' .. i }
      end
      local _, win_opts = whichkey.layout(many)
      assert.is_true(win_opts.row >= 0)
    end)
  end)

  describe('descend', function()
    it('executes directly with no popup for a single unambiguous leaf', function()
      local called = false
      vim.keymap.set('n', '<leader>x', function()
        called = true
      end, { desc = 'do x' })

      local wins_before = #vim.api.nvim_list_wins()
      whichkey.descend('n', 0, to_raw('<leader>x'))
      assert.is_true(called)
      assert.are.equal(wins_before, #vim.api.nvim_list_wins())
    end)

    it('opens a popup when there is more than one option, and executes the chosen leaf', function()
      local called_ff, called_fg = false, false
      vim.keymap.set('n', '<leader>ff', function()
        called_ff = true
      end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function()
        called_fg = true
      end, { desc = 'live grep' })

      whichkey.descend('n', 0, to_raw('<leader>'))
      local popup_win = vim.api.nvim_get_current_win()
      assert.are_not.equal('', vim.api.nvim_win_get_config(popup_win).relative)

      feed('f') -- descend into the "f" group's own popup
      feed('g') -- pick "live grep"

      assert.is_false(called_ff)
      assert.is_true(called_fg)
    end)

    it('dismisses without executing anything on <Esc>', function()
      local called = false
      vim.keymap.set('n', '<leader>ff', function()
        called = true
      end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })

      whichkey.descend('n', 0, to_raw('<leader>'))
      feed('<Esc>')

      assert.is_false(called)
      assert.are.same({}, vim.tbl_filter(function(w)
        return vim.api.nvim_win_get_config(w).relative ~= ''
      end, vim.api.nvim_list_wins()))
    end)

    it('dismisses without executing anything on q', function()
      local called = false
      vim.keymap.set('n', '<leader>ff', function()
        called = true
      end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })

      whichkey.descend('n', 0, to_raw('<leader>'))
      feed('q')

      assert.is_false(called)
    end)

    it('notifies and opens nothing when the prefix has no mappings at all', function()
      local orig_notify = vim.notify
      local captured
      vim.notify = function(msg)
        captured = msg
      end
      local wins_before = #vim.api.nvim_list_wins()
      whichkey.descend('n', 0, to_raw('<leader>zzzunbound'))
      vim.notify = orig_notify

      assert.is_not_nil(captured)
      assert.are.equal(wins_before, #vim.api.nvim_list_wins())
    end)
  end)

  describe('show / setup', function()
    it('show opens the popup for a human prefix', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })

      whichkey.show('<leader>')
      local popup_win = vim.api.nvim_get_current_win()
      assert.are_not.equal('', vim.api.nvim_win_get_config(popup_win).relative)
    end)

    it('setup binds each trigger as a keymap that opens the popup', function()
      vim.keymap.set('n', '<leader>ff', function() end, { desc = 'find files' })
      vim.keymap.set('n', '<leader>fg', function() end, { desc = 'live grep' })

      whichkey.setup({ triggers = { '<leader>' } })
      feed('<leader>')

      local popup_win = vim.api.nvim_get_current_win()
      assert.are_not.equal('', vim.api.nvim_win_get_config(popup_win).relative)
      feed('<Esc>')
    end)

    it('setup honors a custom trigger list', function()
      local called = false
      vim.keymap.set('n', ',x', function()
        called = true
      end, { desc = 'comma x' })

      whichkey.setup({ triggers = { ',' } })
      feed(',x')

      assert.is_true(called)
    end)
  end)
end)

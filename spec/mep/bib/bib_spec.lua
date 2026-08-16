local bib = require('mep.bib')

local function make_buf_at(path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, path)
  return buf
end

describe('mep.bib', function()
  local tmp

  before_each(function()
    tmp = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmp .. '/.git', 'p')
  end)

  after_each(function()
    vim.fn.delete(tmp, 'rf')
    pcall(vim.keymap.del, 'n', '<localleader>ir1')
  end)

  describe('entries', function()
    it('flattens entries across every .bib file found for the buffer', function()
      vim.fn.writefile({ '@article{a, title = {A}}' }, tmp .. '/a.bib')
      vim.fn.writefile({ '@book{b, title = {B}}' }, tmp .. '/b.bib')
      local buf = make_buf_at(tmp .. '/notes.org')

      local entries = bib.entries(buf)
      assert.are.equal(2, #entries)
      local keys = {}
      for _, e in ipairs(entries) do
        keys[e.key] = true
      end
      assert.is_true(keys.a)
      assert.is_true(keys.b)
    end)

    it('returns an empty list when no .bib files are found', function()
      local buf = make_buf_at(tmp .. '/notes.org')
      assert.are.same({}, bib.entries(buf))
    end)
  end)

  describe('picker', function()
    it('opens a mep.picker instance seeded with the buffer\'s citation entries', function()
      vim.fn.writefile({ '@article{smith2020, title = {A Great Paper}, author = {Smith, John}, year = {2020}}' }, tmp .. '/refs.bib')
      local buf = make_buf_at(tmp .. '/notes.org')
      vim.api.nvim_set_current_buf(buf)

      bib.picker()

      local win = vim.api.nvim_get_current_win()
      assert.are.equal('editor', vim.api.nvim_win_get_config(win).relative)
      vim.api.nvim_win_close(win, true)
    end)

    it('captures entry_to_string/on_select via a stubbed mep.picker.start', function()
      vim.fn.writefile({ '@article{smith2020, title = {A Great Paper}, author = {Smith, John}, year = {2020}}' }, tmp .. '/refs.bib')
      local buf = make_buf_at(tmp .. '/notes.org')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'see xx' })
      vim.api.nvim_set_current_buf(buf)
      -- Normal-mode cursor placement clamps to the last character, not
      -- one-past-the-end — insert mode has to be active for column 6
      -- (true end-of-line) to stick, same as mep.snippet's own spec.
      vim.cmd('startinsert')
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      vim.cmd('stopinsert')

      local picker_mod = require('mep.picker')
      local orig_start = picker_mod.start
      local captured
      picker_mod.start = function(opts)
        captured = opts
      end

      bib.picker()
      picker_mod.start = orig_start

      assert.are.equal('Citations', captured.prompt_title)
      assert.are.equal(1, #captured.items)
      local item = captured.items[1]
      assert.are.equal('smith2020', item.key)
      assert.matches('smith2020 — A Great Paper %(Smith, John, 2020%)', captured.entry_to_string(item))

      captured.on_select(item)
      assert.are.same({ 'see xx[cite:@smith2020]' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)
  end)

  describe('setup', function()
    it('binds the configured insert keymap', function()
      bib.setup({ keymaps = { insert = { '<localleader>ir1' } } })
      local resolved = vim.api.nvim_replace_termcodes('<localleader>ir1', true, false, true)
      local found = false
      for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
        if m.lhs == resolved then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('returns the resolved options', function()
      local options = bib.setup({ keymaps = { insert = { '<localleader>ir1' } } })
      assert.are.same({ '<localleader>ir1' }, options.keymaps.insert)
    end)
  end)
end)

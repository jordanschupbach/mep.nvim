local picker_mod = require('mep.roam.picker')

local scratch_dir = '/tmp/mep-roam-picker-spec'

local function write_file(rel, lines)
  local path = scratch_dir .. '/' .. rel
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.roam.picker', function()
  local bufnr, win

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(bufnr, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
  end)

  after_each(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('picker_opts', function()
    it('lists notes by title', function()
      write_file('a.org', { '#+TITLE: My Note', '* H' })
      local opts = picker_mod.picker_opts({ scratch_dir })
      assert.are.equal('Roam Notes', opts.prompt_title)
      assert.are.equal(1, #opts.items)
      assert.are.equal('My Note', opts.entry_to_string(opts.items[1]))
    end)

    it('on_select inserts a [[id:...][title]] link at the cursor', function()
      write_file('b.org', { '#+TITLE: Linked Note', '* H' })
      local opts = picker_mod.picker_opts({ scratch_dir })
      local item = opts.items[1]

      -- Cursor positioned at a genuine mid-line column (not end-of-line,
      -- which has its own clamping edge case unrelated to what this
      -- test is checking) so the insertion point is unambiguous.
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'See here: END' })
      vim.api.nvim_win_set_cursor(win, { 1, #'See here: ' })
      opts.on_select(item)

      local text = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
      assert.are.equal('See here: [[id:' .. item.id .. '][Linked Note]]END', text)
    end)

    it('has a preview function', function()
      write_file('c.org', { '#+TITLE: Has Preview', '* H' })
      local opts = picker_mod.picker_opts({ scratch_dir })
      assert.is_function(opts.preview)
    end)
  end)
end)

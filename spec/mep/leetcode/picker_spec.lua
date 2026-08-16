local picker_mod = require('mep.leetcode.picker')

local scratch_dir = '/tmp/mep-leetcode-picker-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.leetcode.picker', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('picker_opts', function()
    it('lists local problems with title and difficulty', function()
      write_file('a.org', { '#+TITLE: Two Sum', '#+PROPERTY: LEETCODE_DIFFICULTY Easy' })
      local opts = picker_mod.picker_opts(scratch_dir)
      assert.are.equal('LeetCode Problems', opts.prompt_title)
      assert.are.equal(1, #opts.items)
      assert.are.equal('Two Sum [Easy]', opts.entry_to_string(opts.items[1]))
    end)

    it('omits the difficulty suffix when there is none', function()
      write_file('b.org', { '#+TITLE: No Difficulty' })
      local opts = picker_mod.picker_opts(scratch_dir)
      assert.are.equal('No Difficulty', opts.entry_to_string(opts.items[1]))
    end)

    it('on_select opens the problem file', function()
      local path = write_file('c.org', { '#+TITLE: Openable' })
      local opts = picker_mod.picker_opts(scratch_dir)
      opts.on_select(opts.items[1])
      assert.are.equal(vim.fn.fnamemodify(path, ':p'), vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p'))
    end)

    it('has a preview function', function()
      write_file('d.org', { '#+TITLE: Has Preview' })
      local opts = picker_mod.picker_opts(scratch_dir)
      assert.is_function(opts.preview)
    end)
  end)
end)

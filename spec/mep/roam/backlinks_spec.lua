local backlinks = require('mep.roam.backlinks')
local config = require('mep.roam.config')

local scratch_dir = '/tmp/mep-roam-backlinks-spec'

local function write_file(rel, lines)
  local path = scratch_dir .. '/' .. rel
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)
  return path
end

describe('mep.roam.backlinks', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    -- Deterministic open/close in tests — animation is its own concern
    -- (see spec/mep/dap/sidebar_spec.lua for the same convention).
    config.setup({ sidebar = { animate = false } })
  end)

  after_each(function()
    backlinks._reset()
    config.options = saved_options
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('sections', function()
    it('shows a placeholder when there is no note buffer', function()
      local sections = backlinks.sections()
      assert.matches('No note buffer', sections[1].widgets[1].text)
    end)

    it('shows a placeholder when the current buffer has no headline', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'no headline' })
      vim.api.nvim_set_current_buf(buf)
      backlinks.open()
      assert.matches('no headline/ID yet', backlinks.sections()[1].widgets[1].text)
    end)

    it('shows "No backlinks" for a note with an ID but nothing linking to it', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '* A Note' })
      vim.api.nvim_set_current_buf(buf)
      backlinks.open()
      assert.matches('No backlinks', backlinks.sections()[1].widgets[1].text)
    end)

    it('lists a note linking to the current buffer\'s ID', function()
      config.setup({ roam_dirs = { scratch_dir }, sidebar = { animate = false } })
      write_file('linker.org', { '* Linker' })

      local target_path = write_file('target.org', { '* Target' })
      local target_buf = vim.fn.bufadd(target_path)
      vim.fn.bufload(target_buf)
      local id = require('mep.org.id').get_or_create(target_buf, 1)

      -- Write the link only now that we know the real generated ID.
      local linker_buf = vim.fn.bufadd(scratch_dir .. '/linker.org')
      vim.fn.bufload(linker_buf)
      vim.api.nvim_buf_set_lines(linker_buf, 0, -1, false, { '* Linker', '[[id:' .. id .. '][Target]]' })

      vim.api.nvim_set_current_buf(target_buf)
      backlinks.refresh()
      local sections = backlinks.sections()
      assert.matches('Linker', sections[1].widgets[1].text)
    end)
  end)

  describe('open/close/toggle', function()
    it('open() shows the panel and toggle()/close() hide it', function()
      backlinks.open()
      assert.is_true(backlinks.is_open())
      backlinks.close()
      assert.is_false(backlinks.is_open())
      backlinks.toggle()
      assert.is_true(backlinks.is_open())
      backlinks.toggle()
      assert.is_false(backlinks.is_open())
    end)
  end)

  describe('redraw on refresh', function()
    it('reflects a buffer switch after refresh()', function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { '* Buf One' })
      vim.api.nvim_set_current_buf(buf1)
      backlinks.open()

      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf2)
      backlinks.refresh()

      local text = table.concat(vim.api.nvim_buf_get_lines(backlinks.panel().buf, 0, -1, false), '\n')
      assert.matches('no headline/ID yet', text)
    end)
  end)
end)

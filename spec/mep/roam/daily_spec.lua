local daily = require('mep.roam.daily')

local scratch_dir = '/tmp/mep-roam-daily-spec'

describe('mep.roam.daily', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('today_path', function()
    it('builds roam_dirs[1]/daily/YYYY-MM-DD.org', function()
      local path = daily.today_path({ scratch_dir })
      assert.are.equal(scratch_dir .. '/daily/' .. os.date('%Y-%m-%d') .. '.org', path)
    end)

    it('returns nil with no configured roam_dirs', function()
      assert.is_nil(daily.today_path({}))
      assert.is_nil(daily.today_path(nil))
    end)
  end)

  describe('open_today', function()
    it('notifies and does nothing with no configured roam_dirs', function()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      daily.open_today({}, '#+TITLE: %T')
      vim.notify = orig_notify
      assert.matches('no roam_dirs configured', notified)
    end)

    it('creates the file with expanded template content when missing', function()
      daily.open_today({ scratch_dir }, '#+TITLE: Today\n\n* Journal\nEntry text.')
      local path = daily.today_path({ scratch_dir })
      assert.are.equal(1, vim.fn.filereadable(path))
      local text = table.concat(vim.fn.readfile(path), '\n')
      assert.matches('#%+TITLE: Today', text)
      assert.matches('Entry text%.', text)
    end)

    it('places the cursor at the %? placeholder in a new file', function()
      daily.open_today({ scratch_dir }, 'line one\n%?\nline three')
      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.are.equal(2, cursor[1])
    end)

    it('opens an existing file as-is without re-expanding the template', function()
      local path = daily.today_path({ scratch_dir })
      vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
      vim.fn.writefile({ 'already here' }, path)

      daily.open_today({ scratch_dir }, '#+TITLE: Should Not Appear')

      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      assert.are.equal('already here', text)
    end)
  end)
end)

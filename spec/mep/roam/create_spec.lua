local create = require('mep.roam.create')

local scratch_dir = '/tmp/mep-roam-create-spec'

describe('mep.roam.create', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  describe('slugify', function()
    it('lower-cases, replaces spaces with hyphens, drops other punctuation', function()
      assert.are.equal('my-new-note', create.slugify('My New Note'))
      assert.are.equal('whats-up', create.slugify("What's Up?"))
    end)
  end)

  describe('new_note', function()
    it('creates a file with a headline given a fresh :ID:', function()
      local path = create.new_note('My New Note', { scratch_dir })
      assert.are.equal(scratch_dir .. '/my-new-note.org', path)
      assert.are.equal(1, vim.fn.filereadable(path))

      local bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)
      assert.are.equal('* My New Note', vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
      local id = require('mep.org.property').get(bufnr, 1, 'ID')
      assert.is_not_nil(id)
    end)

    it('persists the ID to disk (write happens synchronously)', function()
      local path = create.new_note('Persisted', { scratch_dir })
      local lines = vim.fn.readfile(path)
      local text = table.concat(lines, '\n')
      assert.matches(':ID:', text)
    end)

    it('returns nil and notifies with no configured roam_dirs', function()
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      local path = create.new_note('X', {})
      vim.notify = orig_notify
      assert.is_nil(path)
      assert.matches('no roam_dirs configured', notified)
    end)
  end)

  describe('new_note_interactive', function()
    it('prompts for a title, creates the note, and opens it', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb('Interactive Note')
      end

      create.new_note_interactive({ scratch_dir })

      vim.ui.input = orig_input
      assert.matches('interactive%-note%.org$', vim.api.nvim_buf_get_name(0))
    end)

    it('creates nothing when the prompt is cancelled', function()
      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(nil)
      end

      create.new_note_interactive({ scratch_dir })

      vim.ui.input = orig_input
      assert.are.same({}, vim.fn.glob(scratch_dir .. '/*.org', false, true))
    end)
  end)
end)

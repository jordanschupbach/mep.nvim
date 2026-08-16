local flashcards = require('mep.flashcards')
local review = require('mep.flashcards.review')

local scratch_dir = '/tmp/mep-flashcards-spec'

local function write_file(name, lines)
  vim.fn.mkdir(scratch_dir, 'p')
  local path = scratch_dir .. '/' .. name
  vim.fn.writefile(lines, path)
  return path
end

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.flashcards', function()
  after_each(function()
    review._reset()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, #scratch_dir) == scratch_dir then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(scratch_dir, 'rf')
  end)

  it('re-exports sm2/state/collect/review', function()
    assert.are.equal(require('mep.flashcards.sm2'), flashcards.sm2)
    assert.are.equal(require('mep.flashcards.state'), flashcards.state)
    assert.are.equal(require('mep.flashcards.collect'), flashcards.collect)
    assert.are.equal(review, flashcards.review)
  end)

  describe('review_session', function()
    it('starts a session over every due card in drill_files', function()
      local path = write_file('a.org', { '* Q :drill:', 'A' })
      flashcards.setup({ drill_files = { path }, keymaps = { review = {} } })
      flashcards.review_session()
      assert.is_true(review.is_active())
    end)

    it('notifies with no session for an empty drill_files', function()
      flashcards.setup({ drill_files = {}, keymaps = { review = {} } })
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end
      flashcards.review_session()
      vim.notify = orig_notify
      assert.is_false(review.is_active())
      assert.matches('no cards due', notified)
    end)
  end)

  describe('setup', function()
    it('binds the configured review keymap', function()
      local keymaps = { review = { '<localleader>fr1' } }
      flashcards.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>fr1', 'n', false, true)))
      del_all(keymaps.review)
    end)

    it('returns the resolved options', function()
      local options = flashcards.setup({ tag = 'card', keymaps = { review = {} } })
      assert.are.equal('card', options.tag)
    end)
  end)
end)

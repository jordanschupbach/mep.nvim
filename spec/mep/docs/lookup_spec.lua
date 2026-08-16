local lookup = require('mep.docs.lookup')
local config = require('mep.docs.config')

describe('mep.docs.lookup', function()
  local saved_options

  before_each(function()
    saved_options = vim.deepcopy(config.options)
  end)

  after_each(function()
    config.options = saved_options
  end)

  describe('url_for', function()
    it('builds a devdocs.io instant-search URL scoped by the curated hint', function()
      local url = lookup.url_for('str', 'python')
      assert.are.equal('https://devdocs.io/#q=' .. vim.uri_encode('python str'), url)
    end)

    it('falls back to an unscoped query for a filetype with no curated hint', function()
      local url = lookup.url_for('foo', 'brainfuck')
      assert.are.equal('https://devdocs.io/#q=' .. vim.uri_encode('foo'), url)
    end)

    it('prefers a config override over the curated hint', function()
      config.setup({ doc_hints = { python = 'python~3.9' } })
      local url = lookup.url_for('str', 'python')
      assert.are.equal('https://devdocs.io/#q=' .. vim.uri_encode('python~3.9 str'), url)
    end)

    it('percent-encodes special characters in the word', function()
      local url = lookup.url_for('Array.prototype.map', 'javascript')
      assert.is_nil(url:match('%s')) -- no raw space made it through unencoded
    end)
  end)

  describe('lookup', function()
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
    end)

    it('opens the built URL for the word under the cursor', function()
      vim.bo[bufnr].filetype = 'python'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'requests' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      local url_mod = require('mep.url')
      local orig_open = url_mod.open
      local opened
      url_mod.open = function(u)
        opened = u
      end
      lookup.lookup(bufnr, win)
      url_mod.open = orig_open

      assert.are.equal(lookup.url_for('requests', 'python'), opened)
    end)

    it('notifies and opens nothing when there is no word under the cursor', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '   ' })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      local url_mod = require('mep.url')
      local orig_open = url_mod.open
      local opened = false
      url_mod.open = function()
        opened = true
      end
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified = msg
      end

      lookup.lookup(bufnr, win)

      url_mod.open = orig_open
      vim.notify = orig_notify

      assert.is_false(opened)
      assert.matches('no word under cursor', notified)
    end)
  end)
end)

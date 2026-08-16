local docs = require('mep.docs')
local generate_mod = require('mep.docs.generate')
local lookup_mod = require('mep.docs.lookup')

local function del_all(lhs_list)
  for _, lhs in ipairs(lhs_list) do
    pcall(vim.keymap.del, 'n', lhs)
  end
end

describe('mep.docs', function()
  it('re-exports mep.docs.templates', function()
    assert.are.equal(require('mep.docs.templates'), docs.templates)
  end)

  describe('setup', function()
    it('binds configured keymaps for generate/lookup', function()
      local keymaps = { generate = { '<localleader>gd' }, lookup = { '<localleader>gl' } }
      docs.setup({ keymaps = keymaps })
      assert.is_not_nil(next(vim.fn.maparg('<localleader>gd', 'n', false, true)))
      assert.is_not_nil(next(vim.fn.maparg('<localleader>gl', 'n', false, true)))
      del_all(keymaps.generate)
      del_all(keymaps.lookup)
    end)

    it('returns the resolved options', function()
      local options = docs.setup({ doc_hints = { python = 'python~3.9' } })
      assert.are.same({ python = 'python~3.9' }, options.doc_hints)
      del_all(options.keymaps.generate)
      del_all(options.keymaps.lookup)
    end)
  end)

  describe('generate/lookup', function()
    local bufnr, win

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      win = vim.api.nvim_open_win(bufnr, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.api.nvim_set_current_win(win)
    end)

    after_each(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('generate() operates on the current buffer/window', function()
      local seen_buf, seen_win
      local orig = generate_mod.generate
      generate_mod.generate = function(b, w)
        seen_buf, seen_win = b, w
      end
      docs.generate()
      generate_mod.generate = orig
      assert.are.equal(bufnr, seen_buf)
      assert.are.equal(win, seen_win)
    end)

    it('lookup() operates on the current buffer/window', function()
      local seen_buf, seen_win
      local orig = lookup_mod.lookup
      lookup_mod.lookup = function(b, w)
        seen_buf, seen_win = b, w
      end
      docs.lookup()
      lookup_mod.lookup = orig
      assert.are.equal(bufnr, seen_buf)
      assert.are.equal(win, seen_win)
    end)
  end)
end)

local keymaps_mod = require('mep.lsp.keymaps')
local config = require('mep.lsp.config')

local function make_buf()
  return vim.api.nvim_create_buf(false, true)
end

local function make_client(supports)
  return {
    id = 7,
    supports_method = function(_, method)
      if supports == nil then
        return true
      end
      return supports[method] == true
    end,
  }
end

describe('mep.lsp.keymaps', function()
  describe('bind', function()
    it('binds gd to vim.lsp.buf.definition', function()
      local buf = make_buf()
      local orig = vim.lsp.buf.definition
      local called = false
      vim.lsp.buf.definition = function()
        called = true
      end
      keymaps_mod.bind(buf, make_client(), config.defaults.keymaps, false)
      vim.api.nvim_set_current_buf(buf)
      vim.cmd('normal gd')
      vim.lsp.buf.definition = orig
      assert.is_true(called)
    end)

    it('binds gD/gr/gi to declaration/references/implementation', function()
      local buf = make_buf()
      vim.api.nvim_set_current_buf(buf)
      local calls = {}
      local orig = { declaration = vim.lsp.buf.declaration, references = vim.lsp.buf.references, implementation = vim.lsp.buf.implementation }
      vim.lsp.buf.declaration = function()
        calls.declaration = true
      end
      vim.lsp.buf.references = function()
        calls.references = true
      end
      vim.lsp.buf.implementation = function()
        calls.implementation = true
      end

      keymaps_mod.bind(buf, make_client(), config.defaults.keymaps, false)
      vim.cmd('normal gD')
      vim.cmd('normal gr')
      vim.cmd('normal gi')

      vim.lsp.buf.declaration = orig.declaration
      vim.lsp.buf.references = orig.references
      vim.lsp.buf.implementation = orig.implementation

      assert.is_true(calls.declaration)
      assert.is_true(calls.references)
      assert.is_true(calls.implementation)
    end)

    it('binds K to hover', function()
      local buf = make_buf()
      vim.api.nvim_set_current_buf(buf)
      local orig = vim.lsp.buf.hover
      local called = false
      vim.lsp.buf.hover = function()
        called = true
      end
      keymaps_mod.bind(buf, make_client(), config.defaults.keymaps, false)
      vim.cmd('normal K')
      vim.lsp.buf.hover = orig
      assert.is_true(called)
    end)

    it('sets a desc on every bound keymap', function()
      local buf = make_buf()
      keymaps_mod.bind(buf, make_client(), config.defaults.keymaps, false)
      local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
      local by_lhs = {}
      for _, m in ipairs(maps) do
        by_lhs[m.lhs] = m
      end
      assert.are.equal('lsp: goto definition', by_lhs.gd.desc)
      assert.are.equal('lsp: hover', by_lhs.K.desc)
    end)

    it('honors a custom keymaps override', function()
      local buf = make_buf()
      keymaps_mod.bind(buf, make_client(), { hover = { '<F5>' } }, false)
      local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
      local found = false
      for _, m in ipairs(maps) do
        if m.lhs == '<F5>' then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  describe('native completion', function()
    it('enables completion when the client supports it and completion_enabled is true', function()
      local buf = make_buf()
      local orig = vim.lsp.completion.enable
      local captured
      vim.lsp.completion.enable = function(...)
        captured = { ... }
      end
      keymaps_mod.bind(buf, make_client({ ['textDocument/completion'] = true }), config.defaults.keymaps, true)
      vim.lsp.completion.enable = orig
      assert.are.same({ true, 7, buf, { autotrigger = true } }, captured)
    end)

    it('does not enable completion when the client does not support it', function()
      local buf = make_buf()
      local orig = vim.lsp.completion.enable
      local called = false
      vim.lsp.completion.enable = function()
        called = true
      end
      keymaps_mod.bind(buf, make_client({}), config.defaults.keymaps, true)
      vim.lsp.completion.enable = orig
      assert.is_false(called)
    end)

    it('does not enable completion when completion_enabled is false', function()
      local buf = make_buf()
      local orig = vim.lsp.completion.enable
      local called = false
      vim.lsp.completion.enable = function()
        called = true
      end
      keymaps_mod.bind(buf, make_client({ ['textDocument/completion'] = true }), config.defaults.keymaps, false)
      vim.lsp.completion.enable = orig
      assert.is_false(called)
    end)
  end)
end)

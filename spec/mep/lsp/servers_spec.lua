local servers = require('mep.lsp.servers')

describe('mep.lsp.servers', function()
  describe('registry', function()
    it('every entry has cmd/filetypes/root_markers', function()
      for name, cfg in pairs(servers.registry) do
        assert.is_table(cfg.cmd, name .. ' missing cmd')
        assert.is_true(#cfg.cmd > 0, name .. ' cmd is empty')
        assert.is_table(cfg.filetypes, name .. ' missing filetypes')
        assert.is_true(#cfg.filetypes > 0, name .. ' filetypes is empty')
        assert.is_table(cfg.root_markers, name .. ' missing root_markers')
        assert.is_true(#cfg.root_markers > 0, name .. ' root_markers is empty')
      end
    end)

    it('includes common well-known servers', function()
      assert.is_not_nil(servers.registry.lua_ls)
      assert.is_not_nil(servers.registry.pyright)
      assert.is_not_nil(servers.registry.gopls)
      assert.is_not_nil(servers.registry.rust_analyzer)
      assert.is_not_nil(servers.registry.clangd)
    end)

    it('lua_ls covers lua files', function()
      assert.is_true(vim.tbl_contains(servers.registry.lua_ls.filetypes, 'lua'))
    end)
  end)

  describe('serve_d', function()
    local handler

    before_each(function()
      handler = servers.registry.serve_d.handlers['window/showMessageRequest']
    end)

    it('silently declines a DCD-outdated message request instead of prompting', function()
      local result = handler(nil, { message = 'DCD is outdated. (target=1.2.3, installed=none)', actions = {} }, {}, {})
      -- vim.NIL, not Lua nil: this return value becomes the literal
      -- JSON-RPC response sent to the server, and a bare nil there means
      -- "no response at all" to vim.lsp.rpc's own dispatcher, not "null".
      assert.are.equal(vim.NIL, result)
    end)

    it('still forwards any other message request to the default handler', function()
      local orig = vim.lsp.handlers['window/showMessageRequest']
      local received
      vim.lsp.handlers['window/showMessageRequest'] = function(_, result)
        received = result
        return 'forwarded'
      end

      local ret = handler(nil, { message = 'Some other prompt' }, {}, {})

      vim.lsp.handlers['window/showMessageRequest'] = orig
      assert.are.equal('Some other prompt', received.message)
      assert.are.equal('forwarded', ret)
    end)
  end)

  describe('names', function()
    it('returns every registry key, sorted', function()
      local names = servers.names()
      local expected = vim.tbl_keys(servers.registry)
      table.sort(expected)
      assert.are.same(expected, names)
    end)
  end)
end)

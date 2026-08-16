local lsp = require('mep.docs.lsp')

describe('mep.docs.lsp', function()
  describe('parse', function()
    it('returns the active signature name and string-shaped parameter labels', function()
      local result = {
        activeSignature = 0,
        signatures = {
          { label = 'add(x, y)', parameters = { { label = 'x' }, { label = 'y' } } },
        },
      }
      local name, params = lsp.parse(result)
      assert.are.equal('add', name)
      assert.are.same({ 'x', 'y' }, params)
    end)

    it('slices [start, end]-shaped parameter labels out of the signature label', function()
      local result = {
        signatures = {
          { label = 'add(x: int, y: int)', parameters = { { label = { 4, 10 } }, { label = { 12, 18 } } } },
        },
      }
      local _, params = lsp.parse(result)
      assert.are.same({ 'x: int', 'y: int' }, params)
    end)

    it('respects a non-zero activeSignature index (overload resolution)', function()
      local result = {
        activeSignature = 1,
        signatures = {
          { label = 'add(a)', parameters = { { label = 'a' } } },
          { label = 'add(a, b)', parameters = { { label = 'a' }, { label = 'b' } } },
        },
      }
      local name, params = lsp.parse(result)
      assert.are.equal('add', name)
      assert.are.equal(2, #params)
    end)

    it('returns nil for a response with no signatures', function()
      assert.is_nil(lsp.parse({ signatures = {} }))
      assert.is_nil(lsp.parse(nil))
    end)

    it('returns an empty params list for a zero-argument signature', function()
      local _, params = lsp.parse({ signatures = { { label = 'ping()', parameters = {} } } })
      assert.are.same({}, params)
    end)
  end)

  describe('request', function()
    local orig_get_clients, orig_make_position_params

    before_each(function()
      orig_get_clients = vim.lsp.get_clients
      orig_make_position_params = vim.lsp.util.make_position_params
      vim.lsp.util.make_position_params = function()
        return { position = { line = 0, character = 0 } }
      end
    end)

    after_each(function()
      vim.lsp.get_clients = orig_get_clients
      vim.lsp.util.make_position_params = orig_make_position_params
    end)

    local function make_client(responder)
      return {
        name = 'test_ls',
        offset_encoding = 'utf-16',
        request = function(_, method, _params, handler, bufnr)
          assert.are.equal('textDocument/signatureHelp', method)
          responder(handler, bufnr)
        end,
      }
    end

    it('calls back with nil, nil when no client is attached', function()
      vim.lsp.get_clients = function()
        return {}
      end
      local name, params
      lsp.request(1, 0, function(n, p)
        name, params = n, p
      end)
      assert.is_nil(name)
      assert.is_nil(params)
    end)

    it('calls back with the parsed name/params from the first attached client', function()
      vim.lsp.get_clients = function()
        return {
          make_client(function(handler)
            handler(nil, { signatures = { { label = 'add(x)', parameters = { { label = 'x' } } } } })
          end),
        }
      end
      local name, params
      lsp.request(1, 0, function(n, p)
        name, params = n, p
      end)
      assert.are.equal('add', name)
      assert.are.same({ 'x' }, params)
    end)

    it('calls back with nil, nil on a request error', function()
      vim.lsp.get_clients = function()
        return {
          make_client(function(handler)
            handler({ message = 'boom' }, nil)
          end),
        }
      end
      local name, params
      lsp.request(1, 0, function(n, p)
        name, params = n, p
      end)
      assert.is_nil(name)
      assert.is_nil(params)
    end)
  end)
end)

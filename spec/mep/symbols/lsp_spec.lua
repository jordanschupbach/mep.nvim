local lsp = require('mep.symbols.lsp')

local function range(start_line, start_char, end_line, end_char)
  return {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line, character = end_char },
  }
end

describe('mep.symbols.lsp', function()
  describe('flatten', function()
    it('flattens a hierarchical DocumentSymbol[] result in document order, with depth', function()
      local raw = {
        {
          name = 'Foo',
          kind = 5, -- Class
          range = range(0, 0, 10, 0),
          children = {
            {
              name = 'bar',
              kind = 6, -- Method
              range = range(1, 2, 1, 20),
            },
            {
              name = 'baz',
              kind = 6,
              range = range(2, 2, 2, 20),
            },
          },
        },
        {
          name = 'top_level_fn',
          kind = 12, -- Function
          range = range(12, 0, 14, 0),
        },
      }

      local flat = lsp.flatten(raw)
      assert.are.equal(4, #flat)

      assert.are.equal('Foo', flat[1].name)
      assert.are.equal('Class', flat[1].kind_name)
      assert.are.equal(0, flat[1].depth)
      assert.are.equal(1, flat[1].lnum)
      assert.are.equal(0, flat[1].col)

      assert.are.equal('bar', flat[2].name)
      assert.are.equal('Method', flat[2].kind_name)
      assert.are.equal(1, flat[2].depth)
      assert.are.equal(2, flat[2].lnum)
      assert.are.equal(2, flat[2].col)

      assert.are.equal('baz', flat[3].name)
      assert.are.equal(1, flat[3].depth)

      assert.are.equal('top_level_fn', flat[4].name)
      assert.are.equal('Function', flat[4].kind_name)
      assert.are.equal(0, flat[4].depth)
      assert.are.equal(13, flat[4].lnum)
    end)

    it('flattens a flat SymbolInformation[] result (location.range, no children)', function()
      local raw = {
        { name = 'GLOBAL', kind = 13, location = { range = range(4, 0, 4, 10) } }, -- Variable
      }
      local flat = lsp.flatten(raw)
      assert.are.equal(1, #flat)
      assert.are.equal('GLOBAL', flat[1].name)
      assert.are.equal('Variable', flat[1].kind_name)
      assert.are.equal(0, flat[1].depth)
      assert.are.equal(5, flat[1].lnum)
    end)

    it('falls back to "Unknown" for an unrecognized kind number', function()
      local flat = lsp.flatten({ { name = 'x', kind = 999, range = range(0, 0, 0, 1) } })
      assert.are.equal('Unknown', flat[1].kind_name)
    end)

    it('returns an empty list for nil/empty input', function()
      assert.are.same({}, lsp.flatten(nil))
      assert.are.same({}, lsp.flatten({}))
    end)
  end)

  describe('request', function()
    local orig_get_clients, orig_make_text_document_params

    before_each(function()
      orig_get_clients = vim.lsp.get_clients
      orig_make_text_document_params = vim.lsp.util.make_text_document_params
      vim.lsp.util.make_text_document_params = function()
        return { uri = 'file:///test' }
      end
    end)

    after_each(function()
      vim.lsp.get_clients = orig_get_clients
      vim.lsp.util.make_text_document_params = orig_make_text_document_params
    end)

    local function make_client(responder)
      return {
        name = 'test_ls',
        request = function(_, method, _params, handler, bufnr)
          assert.are.equal('textDocument/documentSymbol', method)
          responder(handler, bufnr)
        end,
      }
    end

    it('calls back with nil and an error message when no client is attached', function()
      vim.lsp.get_clients = function()
        return {}
      end
      local symbols, err
      lsp.request(1, function(s, e)
        symbols, err = s, e
      end)
      assert.is_nil(symbols)
      assert.is_not_nil(err)
    end)

    it('flattens the result from the first attached client', function()
      vim.lsp.get_clients = function()
        return {
          make_client(function(handler)
            handler(nil, { { name = 'x', kind = 12, range = range(0, 0, 0, 1) } })
          end),
        }
      end
      local symbols, err
      lsp.request(3, function(s, e)
        symbols, err = s, e
      end)
      assert.is_nil(err)
      assert.are.equal(1, #symbols)
      assert.are.equal('x', symbols[1].name)
    end)

    it('calls back with nil and the error message on a request error', function()
      vim.lsp.get_clients = function()
        return {
          make_client(function(handler)
            handler({ message = 'boom' }, nil)
          end),
        }
      end
      local symbols, err
      lsp.request(1, function(s, e)
        symbols, err = s, e
      end)
      assert.is_nil(symbols)
      assert.are.equal('boom', err)
    end)

    it('calls back with an empty list (not an error) for a file with no symbols', function()
      vim.lsp.get_clients = function()
        return {
          make_client(function(handler)
            handler(nil, {})
          end),
        }
      end
      local symbols, err
      lsp.request(1, function(s, e)
        symbols, err = s, e
      end)
      assert.is_nil(err)
      assert.are.same({}, symbols)
    end)

    it('requests against the given bufnr', function()
      local requested_bufnr
      vim.lsp.get_clients = function(opts)
        requested_bufnr = opts.bufnr
        return {
          make_client(function(handler, bufnr)
            assert.are.equal(42, bufnr)
            handler(nil, {})
          end),
        }
      end
      lsp.request(42, function() end)
      assert.are.equal(42, requested_bufnr)
    end)
  end)
end)

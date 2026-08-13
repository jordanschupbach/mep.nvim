local lsp_source = require('mep.completion.sources.lsp')

local function make_client(name, id, responder)
  return {
    name = name,
    id = id,
    offset_encoding = 'utf-16',
    request = function(_, _method, _params, handler, _bufnr)
      responder(handler)
    end,
  }
end

describe('mep.completion.sources.lsp', function()
  local orig_get_clients, orig_make_position_params

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
    orig_make_position_params = vim.lsp.util.make_position_params
    vim.lsp.util.make_position_params = function()
      return {}
    end
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
    vim.lsp.util.make_position_params = orig_make_position_params
  end)

  local function ctx()
    return { bufnr = 1, win = 0 }
  end

  it('returns nothing when no client is attached', function()
    vim.lsp.get_clients = function()
      return {}
    end
    local result
    lsp_source.complete(ctx(), function(items)
      result = items
    end)
    assert.are.same({}, result)
  end)

  it('converts a CompletionList result (items field)', function()
    vim.lsp.get_clients = function()
      return { make_client('lua_ls', 1, function(handler)
        handler(nil, { items = { { label = 'print', insertText = 'print(', kind = 3, detail = 'function' } } })
      end) }
    end
    local result
    lsp_source.complete(ctx(), function(items)
      result = items
    end)
    assert.are.equal(1, #result)
    assert.are.equal('print(', result[1].word)
    assert.are.equal('print', result[1].abbr)
    assert.are.equal('Function', result[1].kind)
    assert.are.equal('[lua_ls]', result[1].menu)
    assert.are.equal('function', result[1].info)
  end)

  it('converts a bare CompletionItem[] result', function()
    vim.lsp.get_clients = function()
      return { make_client('lua_ls', 1, function(handler)
        handler(nil, { { label = 'print', kind = 3 } })
      end) }
    end
    local result
    lsp_source.complete(ctx(), function(items)
      result = items
    end)
    assert.are.equal(1, #result)
    assert.are.equal('print', result[1].word) -- falls back to label, no insertText
  end)

  it('defaults kind to Text and info to empty string when absent', function()
    vim.lsp.get_clients = function()
      return { make_client('lua_ls', 1, function(handler)
        handler(nil, { { label = 'x' } })
      end) }
    end
    local result
    lsp_source.complete(ctx(), function(items)
      result = items
    end)
    assert.are.equal('Text', result[1].kind)
    assert.are.equal('', result[1].info)
  end)

  it('merges results from multiple attached clients', function()
    vim.lsp.get_clients = function()
      return {
        make_client('lua_ls', 1, function(handler)
          handler(nil, { { label = 'a' } })
        end),
        make_client('emmylua', 2, function(handler)
          handler(nil, { { label = 'b' } })
        end),
      }
    end
    local result
    lsp_source.complete(ctx(), function(items)
      result = items
    end)
    local words = {}
    for _, it in ipairs(result) do
      words[#words + 1] = it.word
    end
    table.sort(words)
    assert.are.same({ 'a', 'b' }, words)
  end)

  it('handles a nil result (server returned no completions) without erroring', function()
    vim.lsp.get_clients = function()
      return { make_client('lua_ls', 1, function(handler)
        handler(nil, nil)
      end) }
    end
    local result
    assert.has_no.errors(function()
      lsp_source.complete(ctx(), function(items)
        result = items
      end)
    end)
    assert.are.same({}, result)
  end)
end)

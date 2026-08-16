local babelhl = require('mep.org.babelhl')
local babel = require('mep.org.babel')

local NS = vim.api.nvim_create_namespace('mep_org_babel_status')

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })
end

describe('mep.org.babelhl', function()
  local orig_get_clients

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {}
    end
    babel.results_cache = {}
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
    babel.results_cache = {}
  end)

  describe('apply', function()
    it('places one annotation per src block, at the #+end_src line', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src', 'after' })
      babelhl.apply(buf)
      local marks = extmarks(buf)
      assert.are.equal(1, #marks)
      assert.are.equal(2, marks[1][2]) -- 0-indexed row for line 3 (#+end_src)
      assert.are.equal('eol', marks[1][4].virt_text_pos)
    end)

    it('shows "no LSP" when no attached client serves the block\'s filetype', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('no LSP', text)
    end)

    it('shows "LSP ok" when an attached client serves the block\'s filetype', function()
      vim.lsp.get_clients = function()
        return { { config = { filetypes = { 'lua' } } } }
      end
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('LSP ok', text)
    end)

    it('maps csharp to the "cs" filetype for LSP lookup', function()
      vim.lsp.get_clients = function()
        return { { config = { filetypes = { 'cs' } } } }
      end
      local buf = make_buf({ '#+begin_src csharp', 'x', '#+end_src' })
      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('LSP ok', text)
    end)

    it('shows "live" for a block with no :cache header arg', function()
      local buf = make_buf({ '#+begin_src lua', 'print(1)', '#+end_src' })
      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('live', text)
    end)

    it('shows "not cached" for a :cache yes block with nothing cached yet', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('not cached', text)
    end)

    it('shows "cached" for a :cache yes block with a stored result', function()
      local buf = make_buf({ '#+begin_src lua :cache yes', 'print(1)', '#+end_src' })
      local block = babel.at_cursor(buf, 1)
      babel.results_cache[babel.cache_key(buf, block)] = { '1' }

      babelhl.apply(buf)
      local text = extmarks(buf)[1][4].virt_text[1][1]
      assert.matches('cached', text)
      assert.is_nil(text:match('not cached'))
    end)

    it('marks multiple blocks independently', function()
      local buf = make_buf({
        '#+begin_src lua',
        'a',
        '#+end_src',
        '#+begin_src python',
        'b',
        '#+end_src',
      })
      babelhl.apply(buf)
      assert.are.equal(2, #extmarks(buf))
    end)

    it('clears previous marks before recomputing', function()
      local buf = make_buf({ '#+begin_src lua', 'a', '#+end_src' })
      babelhl.apply(buf)
      babelhl.apply(buf)
      assert.are.equal(1, #extmarks(buf))
    end)
  end)

  describe('clear', function()
    it('removes every mark this module set', function()
      local buf = make_buf({ '#+begin_src lua', 'a', '#+end_src' })
      babelhl.apply(buf)
      babelhl.clear(buf)
      assert.are.same({}, extmarks(buf))
    end)
  end)

  describe('define_default_hl', function()
    it('links MepOrgBabelStatus to Comment', function()
      babelhl.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = babelhl.hl_group })
      assert.are.equal('Comment', hl.link)
    end)
  end)
end)

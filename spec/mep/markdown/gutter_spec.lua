-- Pure line-pattern matching + extmarks, no subprocess involved (see
-- spec/README.md) — real buffers are fine here.
local gutter = require('mep.markdown.gutter')
local config = require('mep.markdown.config')

describe('mep.markdown.gutter', function()
  local saved_options
  local sign_ns
  local created_bufs

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    created_bufs[#created_bufs + 1] = bufnr
    return bufnr
  end

  local function marks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, sign_ns, 0, -1, { details = true })
  end

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    config.setup({})
    sign_ns = vim.api.nvim_create_namespace('mep_markdown_gutter')
    created_bufs = {}
  end)

  after_each(function()
    gutter._reset()
    config.options = saved_options
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  describe('attach', function()
    it('places one sign per ATX heading line, showing its level', function()
      local bufnr = make_buf({ '# One', 'body', '## Two', '###### Six' })
      gutter.attach(bufnr)

      local m = marks(bufnr)
      assert.are.equal(3, #m)
      assert.are.equal(0, m[1][2])
      assert.are.equal('①', vim.trim(m[1][4].sign_text))
      assert.are.equal('@markup.heading.1', m[1][4].sign_hl_group)
      assert.are.equal(2, m[2][2])
      assert.are.equal('②', vim.trim(m[2][4].sign_text))
      assert.are.equal(3, m[3][2])
      assert.are.equal('⑥', vim.trim(m[3][4].sign_text))
    end)

    it('ignores 7+ leading #s and #s with no following space', function()
      local bufnr = make_buf({ '####### Seven', '#nospace' })
      gutter.attach(bufnr)
      assert.are.same({}, marks(bufnr))
    end)

    it('uses configured gutter_symbols', function()
      config.setup({ gutter_symbols = { 'a', 'b', 'c', 'd', 'e', 'f' } })
      local bufnr = make_buf({ '## Two' })
      gutter.attach(bufnr)
      local m = marks(bufnr)
      assert.are.equal('b', vim.trim(m[1][4].sign_text))
    end)

    it('is idempotent: attaching an already-attached buffer is a no-op', function()
      local bufnr = make_buf({ '# One' })
      gutter.attach(bufnr)
      gutter.attach(bufnr)
      assert.are.equal(1, #marks(bufnr))
      assert.is_true(gutter.is_attached(bufnr))
    end)

    it('recomputes (debounced) on TextChanged', function()
      local bufnr = make_buf({ '# One' })
      gutter.attach(bufnr)
      assert.are.equal(1, #marks(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { '## Two' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })

      vim.wait(500, function()
        return #marks(bufnr) == 2
      end, 10)
      assert.are.equal(2, #marks(bufnr))
    end)
  end)

  describe('detach', function()
    it('clears signs and stops tracking', function()
      local bufnr = make_buf({ '# One' })
      gutter.attach(bufnr)
      gutter.detach(bufnr)
      assert.are.same({}, marks(bufnr))
      assert.is_false(gutter.is_attached(bufnr))
    end)

    it('is a no-op on a never-attached buffer', function()
      local bufnr = make_buf({ '# One' })
      gutter.detach(bufnr)
      assert.is_false(gutter.is_attached(bufnr))
    end)

    it('is triggered automatically on BufWipeout', function()
      local bufnr = make_buf({ '# One' })
      gutter.attach(bufnr)
      vim.cmd('bwipeout! ' .. bufnr)
      assert.is_false(gutter.is_attached(bufnr))
    end)
  end)

  describe('_reset', function()
    it('detaches every currently tracked buffer', function()
      local a = make_buf({ '# One' })
      local b = make_buf({ '## Two' })
      gutter.attach(a)
      gutter.attach(b)
      gutter._reset()
      assert.is_false(gutter.is_attached(a))
      assert.is_false(gutter.is_attached(b))
    end)
  end)
end)

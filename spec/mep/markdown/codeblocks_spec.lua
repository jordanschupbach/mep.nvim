-- Pure line-pattern matching + extmarks, no subprocess involved (see
-- spec/README.md) — real buffers are fine here.
local codeblocks = require('mep.markdown.codeblocks')

describe('mep.markdown.codeblocks', function()
  local ns
  local created_bufs

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    created_bufs[#created_bufs + 1] = bufnr
    return bufnr
  end

  local function shaded_rows(bufnr)
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      rows[m[2]] = true
    end
    return rows
  end

  before_each(function()
    ns = vim.api.nvim_create_namespace('mep_markdown_codeblocks')
    created_bufs = {}
  end)

  after_each(function()
    codeblocks._reset()
    for _, buf in ipairs(created_bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  describe('attach', function()
    it('shades every line from the opening fence through the closing fence, inclusive', function()
      local bufnr = make_buf({ 'prose', '```lua', 'local x = 1', '```', 'more prose' })
      codeblocks.attach(bufnr)

      local rows = shaded_rows(bufnr)
      assert.is_nil(rows[0]) -- 'prose'
      assert.is_true(rows[1]) -- ```lua
      assert.is_true(rows[2]) -- local x = 1
      assert.is_true(rows[3]) -- ```
      assert.is_nil(rows[4]) -- 'more prose'
    end)

    it('supports ~~~ fences too', function()
      local bufnr = make_buf({ '~~~', 'code', '~~~' })
      codeblocks.attach(bufnr)
      local rows = shaded_rows(bufnr)
      assert.is_true(rows[0])
      assert.is_true(rows[1])
      assert.is_true(rows[2])
    end)

    it('shades an unclosed fence through to the end of the buffer', function()
      local bufnr = make_buf({ '```', 'still typing' })
      codeblocks.attach(bufnr)
      local rows = shaded_rows(bufnr)
      assert.is_true(rows[0])
      assert.is_true(rows[1])
    end)

    it('handles two separate blocks', function()
      local bufnr = make_buf({ '```', 'a', '```', 'text', '```', 'b', '```' })
      codeblocks.attach(bufnr)
      local rows = shaded_rows(bufnr)
      assert.is_true(rows[0])
      assert.is_true(rows[1])
      assert.is_true(rows[2])
      assert.is_nil(rows[3])
      assert.is_true(rows[4])
      assert.is_true(rows[5])
      assert.is_true(rows[6])
    end)

    it('is a no-op for a buffer with no fences', function()
      local bufnr = make_buf({ 'just', 'prose' })
      codeblocks.attach(bufnr)
      assert.are.same({}, shaded_rows(bufnr))
    end)

    it('is idempotent: attaching an already-attached buffer is a no-op', function()
      local bufnr = make_buf({ '```', 'a', '```' })
      codeblocks.attach(bufnr)
      codeblocks.attach(bufnr)
      assert.is_true(codeblocks.is_attached(bufnr))
    end)

    it('recomputes (debounced) on TextChanged', function()
      local bufnr = make_buf({ 'prose' })
      codeblocks.attach(bufnr)
      assert.are.same({}, shaded_rows(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '```', 'code', '```' })
      vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })

      vim.wait(500, function()
        return next(shaded_rows(bufnr)) ~= nil
      end, 10)
      assert.is_true(shaded_rows(bufnr)[0])
    end)
  end)

  describe('detach', function()
    it('clears highlights and stops tracking', function()
      local bufnr = make_buf({ '```', 'a', '```' })
      codeblocks.attach(bufnr)
      codeblocks.detach(bufnr)
      assert.are.same({}, shaded_rows(bufnr))
      assert.is_false(codeblocks.is_attached(bufnr))
    end)

    it('is triggered automatically on BufWipeout', function()
      local bufnr = make_buf({ '```', 'a', '```' })
      codeblocks.attach(bufnr)
      vim.cmd('bwipeout! ' .. bufnr)
      assert.is_false(codeblocks.is_attached(bufnr))
    end)
  end)

  describe('_reset', function()
    it('detaches every currently tracked buffer', function()
      local a = make_buf({ '```', 'a', '```' })
      local b = make_buf({ '```', 'b', '```' })
      codeblocks.attach(a)
      codeblocks.attach(b)
      codeblocks._reset()
      assert.is_false(codeblocks.is_attached(a))
      assert.is_false(codeblocks.is_attached(b))
    end)
  end)
end)

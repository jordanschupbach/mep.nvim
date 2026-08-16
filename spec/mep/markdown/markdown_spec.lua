-- Spies on mep.treesitter.install/activate (both already fully covered
-- by their own specs) rather than re-exercising them — this file is
-- about mep.markdown.setup()'s own wiring: does it register a FileType
-- autocmd scoped to 'markdown', apply header/emphasis highlights (and
-- reapply them on ColorScheme), and attach/detach the gutter.
local markdown = require('mep.markdown.markdown')
local config = require('mep.markdown.config')
local highlights = require('mep.markdown.highlights')
local gutter = require('mep.markdown.gutter')
local tables = require('mep.markdown.tables')
local codeblocks = require('mep.markdown.codeblocks')
local frontmatter = require('mep.markdown.frontmatter')
local ts_install = require('mep.treesitter.install')
local ts_activate = require('mep.treesitter.activate')

describe('mep.markdown.markdown', function()
  local saved_options
  local orig_install, orig_enable_for_buffer

  before_each(function()
    saved_options = vim.deepcopy(config.options)
    orig_install = ts_install.install
    orig_enable_for_buffer = ts_activate.enable_for_buffer
  end)

  after_each(function()
    config.options = saved_options
    ts_install.install = orig_install
    ts_activate.enable_for_buffer = orig_enable_for_buffer
    markdown._reset()
    pcall(vim.api.nvim_del_augroup_by_name, 'MepMarkdown')
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == 'markdown' then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
  end)

  local function stub_install(succeeds)
    local names = {}
    ts_install.install = function(name, on_done)
      names[#names + 1] = name
      on_done(succeeds ~= false)
    end
    return names
  end

  it('returns the merged options', function()
    stub_install()
    local opts = markdown.setup({ headers = false })
    assert.is_false(opts.headers)
  end)

  it('exposes the highlights, gutter, tables, codeblocks, checkbox, fold, linkconceal, and frontmatter submodules', function()
    assert.are.equal(highlights, markdown.highlights)
    assert.are.equal(gutter, markdown.gutter)
    assert.are.equal(tables, markdown.tables)
    assert.are.equal(codeblocks, markdown.codeblocks)
    assert.are.equal(require('mep.markdown.checkbox'), markdown.checkbox)
    assert.are.equal(require('mep.markdown.fold'), markdown.fold)
    assert.are.equal(require('mep.markdown.linkconceal'), markdown.linkconceal)
    assert.are.equal(frontmatter, markdown.frontmatter)
  end)

  describe('highlighting', function()
    -- These two stub ts_activate.enable_for_buffer as a pure spy
    -- (never calling through to the real implementation), unlike mep.
    -- org's equivalent spec — mep.org's own real-activation call-through
    -- is fine for the 'org' grammar, but real `vim.treesitter.start`
    -- with 'markdown' (an injected 'markdown_inline' sub-parser) after
    -- spec/mep/activitybar + spec/mep/chrome/tabline_spec.lua run
    -- reproducibly corrupts the heap in this test harness — a
    -- pre-existing issue in those specs/modules, unrelated to mep.
    -- markdown itself (confirmed via a minimal repro: even a bare
    -- `vim.treesitter.start(buf, 'markdown')` crashes in that exact
    -- position, with none of this file's own code involved at all).
    -- Spying instead of calling through still proves the wiring
    -- (mep.markdown.markdown decides *whether* to activate) without
    -- tripping over that latent bug.
    it('installs both markdown parsers and activates the buffer on success', function()
      local names = stub_install(true)
      local activated = {}
      ts_activate.enable_for_buffer = function(bufnr, opts)
        table.insert(activated, bufnr)
      end

      markdown.setup({ gutter = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_true(vim.tbl_contains(names, 'markdown'))
      assert.is_true(vim.tbl_contains(names, 'markdown_inline'))
      assert.is_true(vim.tbl_contains(activated, buf))
    end)

    it('does not activate when a parser install fails', function()
      stub_install(false)
      local activated = {}
      ts_activate.enable_for_buffer = function(bufnr, opts)
        table.insert(activated, bufnr)
      end

      markdown.setup({ gutter = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.are.same({}, activated)
    end)

    it('does not touch mep.treesitter.install at all when highlight = false', function()
      local called = false
      ts_install.install = function()
        called = true
      end

      markdown.setup({ highlight = false, gutter = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_false(called)
    end)

    it('defines header and emphasis highlight groups on setup', function()
      stub_install()
      -- `:hi clear` (not a bare nvim_set_hl(0, name, {})) is what a real
      -- colorscheme switch does before firing ColorScheme (see mep.
      -- theme.engine.apply) — it's the only thing that actually resets a
      -- group's "already claimed via default=true" tracking, so it's
      -- what this test needs to see define_headers() take effect again.
      vim.cmd('highlight clear')
      local opts = markdown.setup({ gutter = false })
      local hl = vim.api.nvim_get_hl(0, { name = '@markup.heading.1' })
      assert.are.equal('Title', hl.link)
      assert.are.equal(opts.headers, true)
    end)

    it('reapplies header/emphasis highlights on ColorScheme, not just on setup()', function()
      stub_install()
      markdown.setup({ gutter = false })

      local calls = 0
      local orig_define_headers = highlights.define_headers
      highlights.define_headers = function(...)
        calls = calls + 1
        return orig_define_headers(...)
      end

      vim.api.nvim_exec_autocmds('ColorScheme', {})
      highlights.define_headers = orig_define_headers

      assert.are.equal(1, calls)
    end)

    it('defines table and code block highlight groups on setup', function()
      stub_install()
      vim.cmd('highlight clear')
      local opts = markdown.setup({ gutter = false })
      assert.are.equal('Comment', vim.api.nvim_get_hl(0, { name = 'MepMarkdownTableBorder' }).link)
      assert.are.equal('CursorLine', vim.api.nvim_get_hl(0, { name = 'MepMarkdownCodeBlock' }).link)
      assert.is_true(opts.tables)
      assert.is_true(opts.code_blocks)
    end)

    it('does not define table/code-block groups when tables = false, code_blocks = false', function()
      stub_install()
      local orig_define_tables = highlights.define_tables
      local orig_define_code_blocks = highlights.define_code_blocks
      local tables_calls, code_block_calls = 0, 0
      highlights.define_tables = function(...)
        tables_calls = tables_calls + 1
        return orig_define_tables(...)
      end
      highlights.define_code_blocks = function(...)
        code_block_calls = code_block_calls + 1
        return orig_define_code_blocks(...)
      end

      markdown.setup({ gutter = false, tables = false, code_blocks = false })

      highlights.define_tables = orig_define_tables
      highlights.define_code_blocks = orig_define_code_blocks
      assert.are.equal(0, tables_calls)
      assert.are.equal(0, code_block_calls)
    end)
  end)

  describe('gutter', function()
    it('attaches the gutter for buffers opened after setup() when gutter = true', function()
      stub_install()
      markdown.setup({ gutter = true, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# One' })
      vim.bo[buf].filetype = 'markdown'

      assert.is_true(gutter.is_attached(buf))
    end)

    it('does not attach the gutter when gutter = false', function()
      stub_install()
      markdown.setup({ gutter = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_false(gutter.is_attached(buf))
    end)

    it('attaches already-loaded markdown buffers immediately on setup()', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# One' })
      vim.bo[buf].filetype = 'markdown'

      stub_install()
      markdown.setup({ gutter = true, highlight = false })

      assert.is_true(gutter.is_attached(buf))
    end)
  end)

  describe('tables', function()
    it('attaches tables for buffers opened after setup() when tables = true', function()
      stub_install()
      markdown.setup({ tables = true, gutter = false, code_blocks = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_true(tables.is_attached(buf))
    end)

    it('does not attach tables when tables = false', function()
      stub_install()
      markdown.setup({ tables = false, gutter = false, code_blocks = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_false(tables.is_attached(buf))
    end)
  end)

  describe('code_blocks', function()
    it('attaches codeblocks for buffers opened after setup() when code_blocks = true', function()
      stub_install()
      markdown.setup({ code_blocks = true, gutter = false, tables = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_true(codeblocks.is_attached(buf))
    end)

    it('does not attach codeblocks when code_blocks = false', function()
      stub_install()
      markdown.setup({ code_blocks = false, gutter = false, tables = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_false(codeblocks.is_attached(buf))
    end)
  end)

  describe('frontmatter', function()
    it('attaches frontmatter for buffers opened after setup() when frontmatter = true', function()
      stub_install()
      markdown.setup({ frontmatter = true, gutter = false, tables = false, code_blocks = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_true(frontmatter.is_attached(buf))
    end)

    it('does not attach frontmatter when frontmatter = false', function()
      stub_install()
      markdown.setup({ frontmatter = false, gutter = false, tables = false, code_blocks = false, highlight = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      assert.is_false(frontmatter.is_attached(buf))
    end)

    it('defines MepMarkdownFrontmatter on setup', function()
      stub_install()
      vim.cmd('highlight clear')
      markdown.setup({ gutter = false, tables = false, code_blocks = false, highlight = false })
      assert.are.equal('ColorColumn', vim.api.nvim_get_hl(0, { name = 'MepMarkdownFrontmatter' }).link)
    end)
  end)

  describe('checkbox keymap', function()
    it('binds toggle_checkbox buffer-locally when checkbox = true', function()
      stub_install()
      markdown.setup({ checkbox = true, gutter = false, tables = false, code_blocks = false, highlight = false, fold = false, conceal = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [ ] task' })
      vim.bo[buf].filetype = 'markdown'

      local map = vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg('<C-c><C-c>', 'n', false, true)
      end)
      assert.is_not_nil(next(map))
      assert.are.equal(1, map.buffer)
    end)

    it('does not bind toggle_checkbox when checkbox = false', function()
      stub_install()
      markdown.setup({ checkbox = false, gutter = false, tables = false, code_blocks = false, highlight = false, fold = false, conceal = false })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = 'markdown'

      local map = vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg('<C-c><C-c>', 'n', false, true)
      end)
      assert.is_nil(next(map))
    end)
  end)

  describe('fold', function()
    it('sets foldmethod=expr on windows showing the buffer when fold = true', function()
      stub_install()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.bo[buf].filetype = 'markdown'

      markdown.setup({ fold = true, gutter = false, tables = false, code_blocks = false, highlight = false, conceal = false })
      vim.bo[buf].filetype = 'markdown' -- re-trigger FileType now that setup() has registered the autocmd

      assert.are.equal('expr', vim.wo[win].foldmethod)
      vim.api.nvim_win_close(win, true)
    end)

    it('resets foldmethod to manual when fold = false', function()
      stub_install()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.wo[win].foldmethod = 'expr'
      vim.bo[buf].filetype = 'markdown'

      markdown.setup({ fold = false, gutter = false, tables = false, code_blocks = false, highlight = false, conceal = false })
      vim.bo[buf].filetype = 'markdown'

      assert.are.equal('manual', vim.wo[win].foldmethod)
      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe('conceal', function()
    it('sets conceallevel/concealcursor on windows showing the buffer when conceal = true', function()
      stub_install()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.bo[buf].filetype = 'markdown'

      markdown.setup({ conceal = true, gutter = false, tables = false, code_blocks = false, highlight = false, fold = false })
      vim.bo[buf].filetype = 'markdown'

      assert.are.equal(2, vim.wo[win].conceallevel)
      assert.are.equal('nc', vim.wo[win].concealcursor)
      vim.api.nvim_win_close(win, true)
    end)

    it('does not touch conceallevel when conceal = false', function()
      stub_install()
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
      vim.bo[buf].filetype = 'markdown'

      markdown.setup({ conceal = false, gutter = false, tables = false, code_blocks = false, highlight = false, fold = false })
      vim.bo[buf].filetype = 'markdown'

      assert.are.equal(0, vim.wo[win].conceallevel)
      vim.api.nvim_win_close(win, true)
    end)
  end)
end)

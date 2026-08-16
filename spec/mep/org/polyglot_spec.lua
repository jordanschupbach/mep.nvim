local polyglot = require('mep.org.polyglot')

-- Real (but scratch, under vim.fn.tempname()) directory to name every
-- test buffer under below — mep.org.polyglot derives a shadow buffer's
-- (and, for MANIFESTS-listed languages, its on-disk manifest/mirrored-
-- content scaffold's) own directory from the *org* buffer's name,
-- falling back to the current working directory for an unnamed one.
-- Since busted runs from this repo's own root, an unnamed test buffer
-- would otherwise leak a real `.mep-polyglot/` directory into the repo
-- itself on every run (confirmed the hard way while adding the
-- MANIFESTS/mirrored-content tests below).
local scratch_dir = vim.fn.tempname()

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_name, buf, string.format('%s/test-%d.org', scratch_dir, buf))
  return buf
end

describe('mep.org.polyglot', function()
  local created_bufs

  before_each(function()
    created_bufs = {}
  end)

  after_each(function()
    for _, buf in ipairs(created_bufs) do
      polyglot.teardown_buffer(buf)
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  local function buf(lines)
    local b = make_buf(lines)
    created_bufs[#created_bufs + 1] = b
    return b
  end

  describe('sync', function()
    it('creates one shadow buffer per language, blank-padded at the src blocks own line numbers', function()
      local bufnr = buf({
        '* Task',
        '#+begin_src lua',
        'local x = 1',
        '#+end_src',
        '',
        '#+begin_src python',
        'y = 2',
        '#+end_src',
      })
      polyglot.setup_buffer(bufnr, { keymaps = {} })

      local lua_ctx = polyglot.context_at_cursor(bufnr, 3)
      local py_ctx = polyglot.context_at_cursor(bufnr, 7)
      assert.is_not_nil(lua_ctx)
      assert.is_not_nil(py_ctx)
      assert.are.equal('lua', lua_ctx.ft)
      assert.are.equal('python', py_ctx.ft)

      local lua_lines = vim.api.nvim_buf_get_lines(lua_ctx.shadow_bufnr, 0, -1, false)
      assert.are.same({ '', '', 'local x = 1', '', '', '', '', '' }, lua_lines)

      local py_lines = vim.api.nvim_buf_get_lines(py_ctx.shadow_bufnr, 0, -1, false)
      assert.are.same({ '', '', '', '', '', '', 'y = 2', '' }, py_lines)
    end)

    it('re-syncs an existing shadow buffer in place rather than recreating it', function()
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local first = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr

      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'local x = 2' })
      polyglot.sync(bufnr)

      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.equal(first, ctx.shadow_bufnr)
      assert.are.same({ '', 'local x = 2', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)
  end)

  describe('entry-point wrapping (compiled languages)', function()
    it('wraps a C block with :main yes in int main(void) { ... return 0; }', function()
      local bufnr = buf({ '#+begin_src C :main yes :results output', 'printf("hi");', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ 'int main(void) {', 'printf("hi");', 'return 0; }' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('does not wrap a block with :main no, since it already defines its own entry point', function()
      local bufnr = buf({ '#+begin_src C :main no', 'int main() { return 0; }', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ '', 'int main() { return 0; }', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('does not wrap by default, with no :main header arg at all', function()
      local bufnr = buf({ '#+begin_src C', 'int main() { return 0; }', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ '', 'int main() { return 0; }', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('wraps rust in fn main() { ... } when the block sets :main yes', function()
      local bufnr = buf({ '#+begin_src rust :main yes', 'println!("hi");', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ 'fn main() {', 'println!("hi");', '}' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('wraps go in package main; func main() { ... } when the block sets :main yes', function()
      local bufnr = buf({ '#+begin_src go :main yes', 'fmt.Println("hi")', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ 'package main; func main() {', 'fmt.Println("hi")', '}' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('does not wrap languages with no entry-point convention (python, lua, ...)', function()
      local bufnr = buf({ '#+begin_src python', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.same({ '', 'x = 1', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)
  end)

  describe('on-disk manifests (rust, go)', function()
    it('writes a Cargo.toml declaring the shadow buffer as a [[bin]], and a blanket .gitignore', function()
      local bufnr = buf({ '#+begin_src rust', 'println!("hi");', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local shadow_path = vim.api.nvim_buf_get_name(ctx.shadow_bufnr)
      local dir = vim.fn.fnamemodify(shadow_path, ':h')

      assert.are.equal(1, vim.fn.filereadable(dir .. '/Cargo.toml'))
      local cargo_toml = vim.fn.readfile(dir .. '/Cargo.toml')
      assert.is_true(vim.tbl_contains(cargo_toml, 'path = "shadow.rs"'))

      local root = vim.fn.fnamemodify(dir, ':h')
      assert.are.equal(1, vim.fn.filereadable(root .. '/.gitignore'))
      assert.are.same({ '*' }, vim.fn.readfile(root .. '/.gitignore'))
    end)

    it('writes a go.mod for a go block', function()
      local bufnr = buf({ '#+begin_src go', 'fmt.Println("hi")', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.shadow_bufnr), ':h')

      assert.are.equal(1, vim.fn.filereadable(dir .. '/go.mod'))
      assert.are.same({ 'module shadow', '', 'go 1.21' }, vim.fn.readfile(dir .. '/go.mod'))
    end)

    it('mirrors the shadow buffer own live content to real disk for a MANIFESTS language, unlike every other language', function()
      local bufnr = buf({ '#+begin_src rust', 'println!("hi");', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local shadow_path = vim.api.nvim_buf_get_name(ctx.shadow_bufnr)

      assert.are.equal(1, vim.fn.filereadable(shadow_path))
      assert.are.same(vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false), vim.fn.readfile(shadow_path))

      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'println!("changed");' })
      polyglot.sync(bufnr)
      assert.are.same(vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false), vim.fn.readfile(shadow_path))
    end)

    it('deletes the whole scaffold directory (manifest, .gitignore, mirrored content) on teardown', function()
      local bufnr = buf({ '#+begin_src rust', 'println!("hi");', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local root = vim.fn.fnamemodify(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.shadow_bufnr), ':h'), ':h')
      assert.are.equal(1, vim.fn.isdirectory(root))

      polyglot.teardown_buffer(bufnr)

      assert.are.equal(0, vim.fn.isdirectory(root))
    end)
  end)

  describe('ensure_language_parsers', function()
    local ts_install = require('mep.treesitter.install')
    local orig_install

    before_each(function()
      orig_install = ts_install.install
    end)

    after_each(function()
      ts_install.install = orig_install
    end)

    it('installs the distinct tree-sitter parser for every src block language, deduped', function()
      local bufnr = buf({
        '#+begin_src lua', 'a', '#+end_src',
        '#+begin_src lua', 'b', '#+end_src',
        '#+begin_src C++', 'c', '#+end_src',
      })
      local requested = {}
      ts_install.install = function(name, on_done)
        requested[#requested + 1] = name
        on_done(true)
      end

      polyglot.ensure_language_parsers(bufnr, function() end)

      table.sort(requested)
      assert.are.same({ 'cpp', 'lua' }, requested)
    end)

    it('normalizes a divergent language spelling to its real tree-sitter parser name', function()
      local bufnr = buf({ '#+begin_src C++', 'x', '#+end_src' })
      local requested
      ts_install.install = function(name, on_done)
        requested = name
        on_done(true)
      end

      polyglot.ensure_language_parsers(bufnr, function() end)

      assert.are.equal('cpp', requested)
    end)

    it('calls on_installed only for a language that actually became available', function()
      local bufnr = buf({
        '#+begin_src lua', 'a', '#+end_src',
        '#+begin_src perl', 'b', '#+end_src',
      })
      ts_install.install = function(name, on_done)
        on_done(name == 'lua')
      end

      local installed = {}
      polyglot.ensure_language_parsers(bufnr, function(ts_lang)
        installed[#installed + 1] = ts_lang
      end)

      assert.are.same({ 'lua' }, installed)
    end)
  end)

  describe('shadow buffer safety', function()
    it('uses buftype="" (required for vim.lsp.enable to ever consider attaching), not "nofile"', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr

      assert.are.equal('', vim.bo[shadow].buftype)
      assert.is_false(vim.bo[shadow].swapfile)
      assert.is_false(vim.bo[shadow].buflisted)
      assert.is_false(vim.bo[shadow].undofile)
    end)

    it('never reports as modified, despite buftype="" tracking it like a real file', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr
      assert.is_false(vim.bo[shadow].modified)

      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'x = 2' })
      polyglot.sync(bufnr)

      assert.is_false(vim.bo[shadow].modified)
    end)

    it('never actually gets written to disk, even if something tries to :write it', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr
      local path = vim.api.nvim_buf_get_name(shadow)

      vim.api.nvim_buf_call(shadow, function()
        vim.cmd.write()
      end)

      assert.are.equal(0, vim.fn.filereadable(path))
      assert.is_false(vim.bo[shadow].modified)
    end)
  end)

  describe('context_at_cursor', function()
    it('returns nil on the #+begin_src/#+end_src delimiter lines themselves', function()
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      assert.is_nil(polyglot.context_at_cursor(bufnr, 1))
      assert.is_nil(polyglot.context_at_cursor(bufnr, 3))
      assert.is_not_nil(polyglot.context_at_cursor(bufnr, 2))
    end)

    it('returns nil outside any src block', function()
      local bufnr = buf({ 'plain text', '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      assert.is_nil(polyglot.context_at_cursor(bufnr, 1))
    end)

    it('returns nil before setup_buffer has ever run for this buffer', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      assert.is_nil(polyglot.context_at_cursor(bufnr, 2))
    end)
  end)

  describe('teardown_buffer / setup_buffer(bufnr, false)', function()
    it('deletes every shadow buffer and clears context', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr
      assert.is_true(vim.api.nvim_buf_is_valid(shadow))

      polyglot.teardown_buffer(bufnr)

      assert.is_false(vim.api.nvim_buf_is_valid(shadow))
      assert.is_nil(polyglot.context_at_cursor(bufnr, 2))
    end)

    it('setup_buffer(bufnr, false) tears down the same way', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr

      polyglot.setup_buffer(bufnr, false)

      assert.is_false(vim.api.nvim_buf_is_valid(shadow))
    end)

    it('is a no-op for a buffer that was never set up', function()
      local bufnr = buf({ 'plain text' })
      assert.has_no.errors(function()
        polyglot.teardown_buffer(bufnr)
      end)
    end)
  end)

  describe('BufWipeout cleanup', function()
    it('tears down a buffer own shadow buffers once it is wiped (deferred via vim.schedule)', function()
      local bufnr = buf({ '#+begin_src lua', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr

      -- Remove from created_bufs since the wipe below already deletes it;
      -- after_each would otherwise try to delete an already-invalid buffer.
      for i, b in ipairs(created_bufs) do
        if b == bufnr then
          table.remove(created_bufs, i)
          break
        end
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })

      local ok = vim.wait(500, function()
        return not vim.api.nvim_buf_is_valid(shadow)
      end)
      assert.is_true(ok)
    end)
  end)

  describe('diagnostics mirroring', function()
    it('mirrors a shadow buffer own diagnostics onto the org buffer, at the same line/col', function()
      local bufnr = buf({ '* Task', '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 3).shadow_bufnr

      local ns = vim.api.nvim_create_namespace('test_mep_polyglot_diag')
      vim.diagnostic.set(ns, shadow, {
        { lnum = 2, col = 0, message = 'unused variable', severity = vim.diagnostic.severity.WARN },
      })

      local ok = vim.wait(500, function()
        return #vim.diagnostic.get(bufnr) > 0
      end)
      assert.is_true(ok)
      local diags = vim.diagnostic.get(bufnr)
      assert.are.equal(1, #diags)
      assert.are.equal(2, diags[1].lnum)
      assert.are.equal('unused variable', diags[1].message)
    end)
  end)

  -- Opens `bufnr` in its own scoped floating window (entered, so
  -- `vim.api.nvim_get_current_buf()`/window `0` resolve to it the way a
  -- real cursor move would) rather than `nvim_set_current_buf`/
  -- `nvim_win_set_cursor(0, ...)` on whatever window happens to be
  -- current — this suite runs inside one long-lived editor session
  -- shared with every other spec file (see spec/README.md), so hijacking
  -- the *real* current window is both unnecessary here and a way to
  -- inherit whatever state an unrelated earlier spec left it in. Always
  -- closes the window again, even if `fn` throws.
  local function with_win(bufnr, cursor, fn)
    local win = vim.api.nvim_open_win(bufnr, true, { relative = 'editor', row = 0, col = 0, width = 20, height = 5 })
    vim.api.nvim_win_set_cursor(win, cursor)
    local ok, err = pcall(fn)
    pcall(vim.api.nvim_win_close, win, true)
    if not ok then
      error(err, 0)
    end
  end

  describe('omnifunc', function()
    it('findstart=1 returns the start column of the identifier under the cursor', function()
      local bufnr = buf({ '#+begin_src lua', 'local xyz', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })

      with_win(bufnr, { 2, 9 }, function()
        assert.are.equal(6, polyglot.omnifunc(1, ''))
      end)
    end)

    it('returns -3 (no completion) when the cursor is not inside a src block', function()
      local bufnr = buf({ 'plain text' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })

      with_win(bufnr, { 1, 1 }, function()
        assert.are.equal(-3, polyglot.omnifunc(0, ''))
      end)
    end)

    it('returns -3 when inside a block but no client is attached to its shadow buffer', function()
      local bufnr = buf({ '#+begin_src lua', 'local xyz', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })

      with_win(bufnr, { 2, 5 }, function()
        assert.are.equal(-3, polyglot.omnifunc(0, 'xyz'))
      end)
    end)
  end)

  describe('keymap bridging', function()
    local function get_callback(bufnr, mode, lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
        if m.lhs == lhs then
          return m.callback
        end
      end
      return nil
    end

    it('falls back to vim.lsp.buf.definition when the cursor is outside any src block', function()
      local bufnr = buf({ 'plain text' })
      polyglot.setup_buffer(bufnr, { keymaps = { goto_definition = { 'gd' } } })

      local orig = vim.lsp.buf.definition
      local called = false
      vim.lsp.buf.definition = function()
        called = true
      end

      with_win(bufnr, { 1, 0 }, function()
        get_callback(bufnr, 'n', 'gd')()
      end)

      vim.lsp.buf.definition = orig
      assert.is_true(called)
    end)

    it('warns instead of erroring when inside a src block with no attached client', function()
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = { hover = { 'K' } } })

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end

      assert.has_no.errors(function()
        with_win(bufnr, { 2, 0 }, function()
          get_callback(bufnr, 'n', 'K')()
        end)
      end)

      vim.notify = orig_notify
      assert.is_true(warned)
    end)
  end)

  describe('status_widget', function()
    it('returns empty text outside any src block, and " <lang> " inside one', function()
      local bufnr = buf({ 'plain text', '#+begin_src python', 'x = 1', '#+end_src' })
      vim.bo[bufnr].filetype = 'org'
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local widget = polyglot.status_widget()

      with_win(bufnr, { 1, 0 }, function()
        assert.are.equal('', widget.text({ win = vim.api.nvim_get_current_win(), bufnr = bufnr }))
      end)
      with_win(bufnr, { 3, 0 }, function()
        assert.are.equal(' python ', widget.text({ win = vim.api.nvim_get_current_win(), bufnr = bufnr }))
      end)
    end)

    it('returns empty text for a non-org buffer', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x = 1' })
      vim.bo[bufnr].filetype = 'lua'

      with_win(bufnr, { 1, 0 }, function()
        assert.are.equal('', polyglot.status_widget().text({ win = vim.api.nvim_get_current_win(), bufnr = bufnr }))
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('carries a MepOrgPolyglotStatus hl group linked to ModeMsg by default', function()
      local widget = polyglot.status_widget()
      assert.are.equal('MepOrgPolyglotStatus', widget.hl)
      polyglot.define_default_hl()
      local hl = vim.api.nvim_get_hl(0, { name = 'MepOrgPolyglotStatus' })
      assert.are.equal('ModeMsg', hl.link)
    end)
  end)
end)

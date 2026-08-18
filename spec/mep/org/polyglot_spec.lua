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

-- Same scratch-not-real-location concern as `scratch_dir` above, but for
-- PER_BLOCK_LANGS (c/cpp): those get their own scaffolding under
-- `vim.fn.stdpath('cache')` rather than next to the org file, so without
-- this every test touching a c/cpp block would otherwise leak a real
-- `mep-polyglot/` directory into this machine's actual Neovim cache dir
-- (confirmed the hard way while adding the tests below).
local cache_dir = vim.fn.tempname()

describe('mep.org.polyglot', function()
  local created_bufs
  local orig_stdpath

  before_each(function()
    created_bufs = {}
    orig_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == 'cache' then
        return cache_dir
      end
      return orig_stdpath(what)
    end
  end)

  after_each(function()
    for _, buf in ipairs(created_bufs) do
      polyglot.teardown_buffer(buf)
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.fn.stdpath = orig_stdpath
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

    it('does not create a shadow buffer for a language whose block the cursor has never visited', function()
      -- Regression test: setup_buffer's first sync() used to eagerly
      -- create (and filetype-tag, triggering real vim.lsp.enable
      -- autostart) a shadow buffer for *every* src-block language the
      -- instant an org buffer was opened — merely opening a file with,
      -- say, a `d` example block could silently start a real `serve-d`
      -- process (if happened to be on PATH) before the cursor had moved
      -- once. Shadow buffers are real, listed-as-buffers Neovim buffers
      -- (buftype=''), so "no new buffer got created" is a solid, fully
      -- black-box way to confirm none of that happened.
      local before = #vim.api.nvim_list_bufs()
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      polyglot.sync(bufnr)

      -- +1 for the org buffer itself; no shadow buffer for `lua` yet.
      assert.are.equal(before + 1, #vim.api.nvim_list_bufs())
    end)

    it('context_at_cursor lazily creates a shadow buffer only the first time a block is actually visited', function()
      local before = #vim.api.nvim_list_bufs()
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      assert.are.equal(before + 1, #vim.api.nvim_list_bufs())

      local ctx = polyglot.context_at_cursor(bufnr, 2)

      assert.are.equal(before + 2, #vim.api.nvim_list_bufs()) -- org buffer + the one new shadow
      assert.are.same({ '', 'local x = 1', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))

      -- Visiting it again reuses the same shadow buffer rather than
      -- creating another one.
      local same_ctx = polyglot.context_at_cursor(bufnr, 2)
      assert.are.equal(ctx.shadow_bufnr, same_ctx.shadow_bufnr)
      assert.are.equal(before + 2, #vim.api.nvim_list_bufs())
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

  describe('per-block shadow buffers (c/cpp)', function()
    it('gives two cpp blocks in one buffer two distinct shadow buffers, each with only its own body', function()
      local bufnr = buf({
        '#+begin_src cpp',
        'int a = 1;',
        '#+end_src',
        '#+begin_src cpp',
        'int b = 2;',
        '#+end_src',
      })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx1 = polyglot.context_at_cursor(bufnr, 2)
      local ctx2 = polyglot.context_at_cursor(bufnr, 5)

      assert.is_not_nil(ctx1)
      assert.is_not_nil(ctx2)
      assert.are_not.equal(ctx1.shadow_bufnr, ctx2.shadow_bufnr)
      assert.are_not.equal(vim.api.nvim_buf_get_name(ctx1.shadow_bufnr), vim.api.nvim_buf_get_name(ctx2.shadow_bufnr))

      assert.are.same({ '', 'int a = 1;', '', '', '', '' }, vim.api.nvim_buf_get_lines(ctx1.shadow_bufnr, 0, -1, false))
      assert.are.same({ '', '', '', '', 'int b = 2;', '' }, vim.api.nvim_buf_get_lines(ctx2.shadow_bufnr, 0, -1, false))
    end)

    it('supports :main yes on more than one block in the same file (the shared-shadow limitation is lifted for c/cpp)', function()
      local bufnr = buf({
        '#+begin_src cpp :main yes',
        'std::cout << "a";',
        '#+end_src',
        '#+begin_src cpp :main yes',
        'std::cout << "b";',
        '#+end_src',
      })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx1 = polyglot.context_at_cursor(bufnr, 2)
      local ctx2 = polyglot.context_at_cursor(bufnr, 5)

      assert.are.same(
        { 'int main() {', 'std::cout << "a";', 'return 0; }', '', '', '' },
        vim.api.nvim_buf_get_lines(ctx1.shadow_bufnr, 0, -1, false)
      )
      assert.are.same(
        { '', '', '', 'int main() {', 'std::cout << "b";', 'return 0; }' },
        vim.api.nvim_buf_get_lines(ctx2.shadow_bufnr, 0, -1, false)
      )
    end)

    it('places c/cpp scaffolding under stdpath("cache"), not next to the org file', function()
      local bufnr = buf({ '#+begin_src cpp', 'int x = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local path = vim.api.nvim_buf_get_name(ctx.shadow_bufnr)
      assert.is_not_nil(path:find(cache_dir, 1, true))
      assert.is_nil(path:find(scratch_dir, 1, true))
    end)

    it('M.sync updates a per-block shadow when its own block body changes', function()
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)

      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'int a = 2;' })
      polyglot.sync(bufnr)

      assert.are.same({ '', 'int a = 2;', '' }, vim.api.nvim_buf_get_lines(ctx.shadow_bufnr, 0, -1, false))
    end)

    it('deletes every per-block shadow buffer and the cache scaffold root on teardown', function()
      local bufnr = buf({
        '#+begin_src cpp',
        'int a = 1;',
        '#+end_src',
        '#+begin_src cpp',
        'int b = 2;',
        '#+end_src',
      })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx1 = polyglot.context_at_cursor(bufnr, 2)
      local ctx2 = polyglot.context_at_cursor(bufnr, 5)
      local root = vim.fn.fnamemodify(vim.fn.fnamemodify(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx1.shadow_bufnr), ':h'), ':h'), ':h')
      assert.are.equal(1, vim.fn.isdirectory(root))

      polyglot.teardown_buffer(bufnr)

      assert.is_false(vim.api.nvim_buf_is_valid(ctx1.shadow_bufnr))
      assert.is_false(vim.api.nvim_buf_is_valid(ctx2.shadow_bufnr))
      assert.are.equal(0, vim.fn.isdirectory(root))
    end)
  end)

  describe('on_block_executed', function()
    local orig_executable, orig_get_clients

    before_each(function()
      orig_executable = vim.fn.executable
      orig_get_clients = vim.lsp.get_clients
      vim.fn.executable = function(name)
        return name == 'g++' and 1 or 0
      end
      vim.lsp.get_clients = function()
        return {}
      end
    end)

    after_each(function()
      vim.fn.executable = orig_executable
      vim.lsp.get_clients = orig_get_clients
    end)

    it('writes a compile_commands.json entry matching the real compile invocation', function()
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local shadow_path = vim.api.nvim_buf_get_name(ctx.shadow_bufnr)
      local dir = vim.fn.fnamemodify(shadow_path, ':h')

      polyglot.on_block_executed(bufnr, 2)

      local cdb_path = dir .. '/compile_commands.json'
      assert.are.equal(1, vim.fn.filereadable(cdb_path))
      local decoded = vim.json.decode(table.concat(vim.fn.readfile(cdb_path), '\n'))
      assert.are.equal(1, #decoded)
      assert.are.equal(dir, decoded[1].directory)
      assert.are.equal(shadow_path, decoded[1].file)
      assert.are.same({ 'g++', '-c', shadow_path }, decoded[1].arguments)
    end)

    it('notifies every client attached to the block shadow buffer via workspace/didChangeWatchedFiles', function()
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local shadow_path = vim.api.nvim_buf_get_name(ctx.shadow_bufnr)
      local dir = vim.fn.fnamemodify(shadow_path, ':h')

      local notified
      vim.lsp.get_clients = function(opts)
        assert.are.equal(ctx.shadow_bufnr, opts.bufnr)
        return {
          {
            notify = function(_, method, params)
              notified = { method = method, params = params }
            end,
          },
        }
      end

      polyglot.on_block_executed(bufnr, 2)

      assert.is_not_nil(notified)
      assert.are.equal('workspace/didChangeWatchedFiles', notified.method)
      assert.are.equal(vim.uri_from_fname(dir .. '/compile_commands.json'), notified.params.changes[1].uri)
      assert.are.equal(2, notified.params.changes[1].type)
    end)

    it('is a no-op (nothing written, no error) when the block was never visited (no shadow yet)', function()
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })

      assert.has_no.errors(function()
        polyglot.on_block_executed(bufnr, 2)
      end)
    end)

    it('is a no-op for a non-c/cpp language', function()
      local bufnr = buf({ '#+begin_src python', 'x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      polyglot.context_at_cursor(bufnr, 2)

      assert.has_no.errors(function()
        polyglot.on_block_executed(bufnr, 2)
      end)
    end)

    it('is a no-op when polyglot was never set up for this buffer', function()
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      assert.has_no.errors(function()
        polyglot.on_block_executed(bufnr, 2)
      end)
    end)

    it('is a no-op when no compiler resolves on PATH', function()
      vim.fn.executable = function()
        return 0
      end
      local bufnr = buf({ '#+begin_src cpp', 'int a = 1;', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local ctx = polyglot.context_at_cursor(bufnr, 2)
      local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.shadow_bufnr), ':h')

      polyglot.on_block_executed(bufnr, 2)

      assert.are.equal(0, vim.fn.filereadable(dir .. '/compile_commands.json'))
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

    it('drops a shadow diagnostic that falls outside that language own block(s) (blank filler lines)', function()
      -- Two languages sharing one org buffer: the lua block is only 1
      -- line long, so its shadow buffer is blank everywhere except line
      -- 3 (the python block's own line 7 included). A whole-file linter
      -- reporting against one of those blank filler lines (e.g. R's
      -- lintr flagging "Remove trailing blank lines") must not surface on
      -- the org buffer at all, and must never land on the *other*
      -- language's real content that happens to share that line number.
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
      local lua_shadow = polyglot.context_at_cursor(bufnr, 3).shadow_bufnr

      local ns = vim.api.nvim_create_namespace('test_mep_polyglot_diag_outside')
      vim.diagnostic.set(ns, lua_shadow, {
        -- Line 7 (0-indexed 6) is blank in the lua shadow buffer (it's
        -- the python block's own body line) but should still be dropped
        -- even though it coincides with real content in *another*
        -- shadow buffer.
        { lnum = 6, col = 0, message = 'Remove trailing blank lines', severity = vim.diagnostic.severity.WARN },
      })

      -- No diagnostic-count change is itself the assertion here, so
      -- there's no event to vim.wait on; DiagnosticChanged for the lua
      -- shadow buffer has already fired synchronously by the time
      -- vim.diagnostic.set above returns.
      local diags = vim.diagnostic.get(bufnr)
      assert.are.equal(0, #diags)
    end)

    it('does not error when a diagnostic arrives for a shadow buffer after its own org buffer is already gone', function()
      -- Regression test: the org buffer's own BufDelete/BufWipeout
      -- teardown is deliberately deferred a tick (vim.schedule — see
      -- setup_buffer's own comment on why), so `state[bufnr]` can still
      -- exist for a buffer that's already `nvim_buf_is_valid() == false`.
      -- A shadow buffer's `DiagnosticChanged` firing in that window
      -- (e.g. a real language server's publishDiagnostics notification
      -- landing asynchronously — surfaced in practice via mep.picker's
      -- preview pane wiring up a real poly-mode session for a buffer
      -- that then gets wiped the moment a selection is made) used to
      -- crash with "Invalid buffer id" from an un-guarded
      -- `vim.diagnostic.set(ns, bufnr, ...)` against the dead buffer.
      local bufnr = buf({ '#+begin_src lua', 'local x = 1', '#+end_src' })
      polyglot.setup_buffer(bufnr, { keymaps = {} })
      local shadow = polyglot.context_at_cursor(bufnr, 2).shadow_bufnr

      vim.api.nvim_buf_delete(bufnr, { force = true }) -- teardown_buffer itself hasn't run yet (scheduled)
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))

      local ns = vim.api.nvim_create_namespace('test_mep_polyglot_diag_after_delete')
      assert.has_no.errors(function()
        vim.diagnostic.set(ns, shadow, {
          { lnum = 0, col = 0, message = 'late diagnostic', severity = vim.diagnostic.severity.WARN },
        })
      end)
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

    it('binds [e/]e to previous/next diagnostic filtered to ERROR severity', function()
      local bufnr = buf({ 'plain text' })
      polyglot.setup_buffer(bufnr, {
        keymaps = { diagnostic_prev_error = { '[e' }, diagnostic_next_error = { ']e' } },
      })

      local orig = { goto_prev = vim.diagnostic.goto_prev, goto_next = vim.diagnostic.goto_next }
      local captured = {}
      vim.diagnostic.goto_prev = function(opts)
        captured.prev = opts
      end
      vim.diagnostic.goto_next = function(opts)
        captured.next = opts
      end

      get_callback(bufnr, 'n', '[e')()
      get_callback(bufnr, 'n', ']e')()

      vim.diagnostic.goto_prev = orig.goto_prev
      vim.diagnostic.goto_next = orig.goto_next

      assert.are.same({ severity = vim.diagnostic.severity.ERROR }, captured.prev)
      assert.are.same({ severity = vim.diagnostic.severity.ERROR }, captured.next)
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

local lsp_mod = require('mep.lsp.lsp')
local config = require('mep.lsp.config')
local servers = require('mep.lsp.servers')

describe('mep.lsp.lsp', function()
  local saved_config
  local orig_lsp_config, orig_lsp_enable, orig_executable, orig_diag_config, orig_get_client
  local orig_completion_type

  before_each(function()
    saved_config = vim.deepcopy(config.options)
    orig_lsp_config = vim.lsp.config
    orig_lsp_enable = vim.lsp.enable
    orig_executable = vim.fn.executable
    orig_diag_config = vim.diagnostic.config
    orig_get_client = vim.lsp.get_client_by_id
    -- never actually resolve a real 'found on PATH' executable during
    -- tests, so a stray vim.lsp.enable() call (if a guard were broken)
    -- could never actually try to spawn something real
    vim.fn.executable = function()
      return 0
    end
  end)

  after_each(function()
    config.options = saved_config
    vim.lsp.config = orig_lsp_config
    vim.lsp.enable = orig_lsp_enable
    vim.fn.executable = orig_executable
    vim.diagnostic.config = orig_diag_config
    vim.lsp.get_client_by_id = orig_get_client
    pcall(vim.api.nvim_del_augroup_by_name, 'MepLsp')
  end)

  describe('setup', function()
    it('registers every curated server config via vim.lsp.config', function()
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      for name in pairs(servers.registry) do
        assert.is_not_nil(registered[name], name .. ' was not registered')
      end
    end)

    it('registers custom servers.* configs too', function()
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({ servers = { my_server = { cmd = { 'my-server' }, filetypes = { 'myft' }, root_markers = { '.git' } } } })

      assert.is_not_nil(registered.my_server)
      assert.are.same({ 'my-server' }, registered.my_server.cmd)
    end)

    it('only enables servers whose cmd[1] is found on PATH', function()
      vim.lsp.config = function() end
      vim.fn.executable = function(exe)
        return exe == 'gopls' and 1 or 0
      end
      local enabled
      vim.lsp.enable = function(names)
        enabled = names
      end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.are.same({ 'gopls' }, enabled)
    end)

    it('does not call vim.lsp.enable at all when nothing is on PATH', function()
      vim.lsp.config = function() end
      local called = false
      vim.lsp.enable = function()
        called = true
      end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.is_false(called)
    end)

    it('enable = false never enables anything, even if found on PATH', function()
      vim.lsp.config = function() end
      vim.fn.executable = function()
        return 1
      end
      local called = false
      vim.lsp.enable = function()
        called = true
      end
      vim.diagnostic.config = function() end

      lsp_mod.setup({ enable = false })

      assert.is_false(called)
    end)

    it('enable = {names} restricts to just those names, still gated on PATH', function()
      vim.lsp.config = function() end
      vim.fn.executable = function()
        return 1
      end
      local enabled
      vim.lsp.enable = function(names)
        enabled = names
      end
      vim.diagnostic.config = function() end

      lsp_mod.setup({ enable = { 'lua_ls', 'pyright' } })

      table.sort(enabled)
      assert.are.same({ 'lua_ls', 'pyright' }, enabled)
    end)

    it('forwards options.diagnostics to vim.diagnostic.config', function()
      vim.lsp.config = function() end
      vim.lsp.enable = function() end
      local captured
      vim.diagnostic.config = function(opts)
        captured = opts
      end

      lsp_mod.setup({ diagnostics = { virtual_text = false } })

      assert.is_false(captured.virtual_text)
    end)

    it('warns and skips setup on Neovim without vim.lsp.config/enable', function()
      -- the real guard is a `has('nvim-0.11')` version check, not a
      -- `type(vim.lsp.config) == 'function'` shape check — `vim.lsp.
      -- config` is actually a *table* with a `__call` metamethod on a
      -- real modern Neovim (confirmed empirically), so a naive shape
      -- check would misreport every real version as "unsupported".
      local orig_has = vim.fn.has
      vim.fn.has = function(feature)
        if feature == 'nvim-0.11' then
          return 0
        end
        return orig_has(feature)
      end
      local diag_called = false
      vim.diagnostic.config = function()
        diag_called = true
      end
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end

      lsp_mod.setup({})

      vim.notify = orig_notify
      vim.fn.has = orig_has
      assert.is_true(warned)
      assert.is_false(diag_called)
    end)

    it('proceeds normally on a real modern Neovim (vim.lsp.config is a callable table, not type "function")', function()
      -- regression test for the bug above: assert the guard doesn't
      -- trip on the *real*, unmocked vim.lsp.config/vim.lsp.enable in
      -- this actual Neovim, only ever mocked elsewhere in this file for
      -- call-capturing purposes.
      local real_config, real_enable = vim.lsp.config, vim.lsp.enable
      local diag_called = false
      vim.diagnostic.config = function()
        diag_called = true
      end
      -- still avoid ever registering a *real* FileType-triggered
      -- autostart in this shared test process — capture instead of
      -- calling through, but keep them as real functions (this is
      -- exactly what type(vim.lsp.config) == 'function' would see as
      -- 'table' and wrongly skip).
      local config_calls = 0
      vim.lsp.config = setmetatable({}, {
        __call = function()
          config_calls = config_calls + 1
        end,
      })
      vim.lsp.enable = function() end

      lsp_mod.setup({})

      vim.lsp.config = real_config
      vim.lsp.enable = real_enable
      assert.is_true(diag_called)
      assert.is_true(config_calls > 0)
    end)
  end)

  describe('clangd --query-driver', function()
    local orig_exepath, orig_fnamemodify

    before_each(function()
      orig_exepath = vim.fn.exepath
      orig_fnamemodify = vim.fn.fnamemodify
    end)

    after_each(function()
      vim.fn.exepath = orig_exepath
      vim.fn.fnamemodify = orig_fnamemodify
    end)

    it('appends --query-driver scoped to resolved compiler directories', function()
      vim.fn.exepath = function(exe)
        if exe == 'gcc' or exe == 'g++' then
          return '/opt/toolchain/bin/' .. exe
        end
        return ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.are.same({ 'clangd', '--query-driver=/opt/toolchain/bin/**' }, registered.clangd.cmd)
    end)

    it('dedupes directories shared by more than one resolved compiler name', function()
      vim.fn.exepath = function(exe)
        if exe == 'gcc' or exe == 'cc' then
          return '/usr/bin/' .. exe
        end
        return ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.are.same({ 'clangd', '--query-driver=/usr/bin/**' }, registered.clangd.cmd)
    end)

    it('does not touch any other server\'s cmd', function()
      vim.fn.exepath = function(exe)
        return exe == 'gcc' and '/usr/bin/gcc' or ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.are.same({ 'gopls' }, registered.gopls.cmd)
      assert.are.same({ 'pyright-langserver', '--stdio' }, registered.pyright.cmd)
    end)

    it('appends nothing when no compiler resolves on PATH', function()
      vim.fn.exepath = function()
        return ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({})

      assert.are.same({ 'clangd' }, registered.clangd.cmd)
    end)

    it('never duplicates a --query-driver a custom clangd override already set', function()
      vim.fn.exepath = function(exe)
        return exe == 'gcc' and '/usr/bin/gcc' or ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({ servers = { clangd = { cmd = { 'clangd', '--query-driver=/custom/**' }, filetypes = { 'cpp' }, root_markers = { '.git' } } } })

      assert.are.same({ 'clangd', '--query-driver=/custom/**' }, registered.clangd.cmd)
    end)

    it('leaves a fully custom (non-stock) clangd cmd untouched', function()
      vim.fn.exepath = function(exe)
        return exe == 'gcc' and '/usr/bin/gcc' or ''
      end
      local registered = {}
      vim.lsp.config = function(name, cfg)
        registered[name] = cfg
      end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      lsp_mod.setup({ servers = { clangd = { cmd = { '/my/own/clangd-wrapper' }, filetypes = { 'cpp' }, root_markers = { '.git' } } } })

      assert.are.same({ '/my/own/clangd-wrapper' }, registered.clangd.cmd)
    end)

    it('does not mutate a user-supplied servers.clangd table in place', function()
      vim.fn.exepath = function(exe)
        return exe == 'gcc' and '/usr/bin/gcc' or ''
      end
      vim.lsp.config = function() end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end

      local user_cfg = { cmd = { 'clangd' }, filetypes = { 'cpp' }, root_markers = { '.git' } }
      lsp_mod.setup({ servers = { clangd = user_cfg } })

      assert.are.same({ 'clangd' }, user_cfg.cmd)
    end)
  end)

  describe('LspAttach wiring', function()
    it('binds keymaps for the attaching client', function()
      vim.lsp.config = function() end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end
      vim.lsp.get_client_by_id = function(id)
        return { id = id, supports_method = function()
          return false
        end }
      end

      lsp_mod.setup({})

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_exec_autocmds('LspAttach', { buffer = buf, data = { client_id = 99 } })

      local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
      local has_gd = false
      for _, m in ipairs(maps) do
        if m.lhs == 'gd' then
          has_gd = true
        end
      end
      assert.is_true(has_gd)
    end)

    it('does nothing if the client id no longer resolves to a real client', function()
      vim.lsp.config = function() end
      vim.lsp.enable = function() end
      vim.diagnostic.config = function() end
      vim.lsp.get_client_by_id = function()
        return nil
      end

      lsp_mod.setup({})

      local buf = vim.api.nvim_create_buf(false, true)
      assert.has_no.errors(function()
        vim.api.nvim_exec_autocmds('LspAttach', { buffer = buf, data = { client_id = 99 } })
      end)
    end)
  end)
end)

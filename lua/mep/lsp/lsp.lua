--- Aggregator for mep's LSP library: registers server configs
--- (`mep.lsp.servers`' curated registry, plus your own `config.servers`)
--- via Neovim >= 0.11's native `vim.lsp.config`/`vim.lsp.enable` —
--- *not* nvim-lspconfig — auto-activating whichever ones are actually
--- found on `PATH`, configures `vim.diagnostic`, and binds the classic
--- `gd`/`gD`/`gr`/`gi`/... keymaps (`mep.lsp.keymaps`) once a client
--- attaches to a buffer.
---
--- No server is ever installed by this library (see mep.lsp.servers's
--- own header comment for why, unlike mep.treesitter's parsers) — only
--- *activated*, and only if its `cmd` is already on `PATH`.
local config = require('mep.lsp.config')
local servers = require('mep.lsp.servers')
local keymaps_mod = require('mep.lsp.keymaps')

local M = {}
M.servers = servers

local augroup = nil

--- The curated registry plus `options.servers`, the latter overriding/
--- extending the former (a whole-entry replace per name, matching
--- `vim.lsp.config(name, cfg)`'s own "merge" semantics being applied
--- next — this is just deciding *which* configs exist to register at
--- all, not the merge itself).
local function all_configs(options)
  local merged = vim.deepcopy(servers.registry)
  for name, cfg in pairs(options.servers) do
    merged[name] = cfg
  end
  return merged
end

local function should_enable(name, enable_opt)
  if enable_opt == true then
    return true
  end
  if type(enable_opt) == 'table' then
    return vim.tbl_contains(enable_opt, name)
  end
  return false
end

--- Whether `cfg.cmd` is (or resolves to) something already on `PATH`.
--- A function-form `cmd` (`vim.lsp.Config`'s other allowed shape) can't
--- be statically checked this way — treated as "assume available",
--- trusting whoever wrote that function knows it's valid.
local function cmd_available(cfg)
  if type(cfg.cmd) ~= 'table' then
    return true
  end
  local exe = cfg.cmd[1]
  return exe ~= nil and vim.fn.executable(exe) == 1
end

--- Compiler driver names clangd may need to query for its system include
--- paths (gcc/g++/clang family) — checked via `vim.fn.exepath` so the
--- resulting `--query-driver` glob only ever trusts binaries this
--- specific machine's own `PATH` already resolves, not an arbitrary
--- wildcard. Without this, clangd falls back to guessed flags with no
--- system include paths at all whenever the real compiler's own search
--- paths aren't wherever clangd's built-in defaults expect (confirmed on
--- NixOS, where headers live under a per-package `/nix/store/<hash>-gcc-
--- .../` path rather than `/usr/include` — but the fix is the same on any
--- system: ask the real compiler where its headers are).
local QUERY_DRIVER_EXES = { 'gcc', 'g++', 'cc', 'c++', 'clang', 'clang++' }

--- `--query-driver=<dir1>/**,<dir2>/**,...` for every `QUERY_DRIVER_EXES`
--- entry actually found on `PATH` (deduped by directory — most systems
--- resolve several of these to the same `bin/` directory), or nil if none
--- were found.
local function query_driver_flag()
  local dirs, seen = {}, {}
  for _, exe in ipairs(QUERY_DRIVER_EXES) do
    local path = vim.fn.exepath(exe)
    if path ~= '' then
      local dir = vim.fn.fnamemodify(path, ':h')
      if not seen[dir] then
        seen[dir] = true
        dirs[#dirs + 1] = dir .. '/**'
      end
    end
  end
  return #dirs > 0 and ('--query-driver=' .. table.concat(dirs, ',')) or nil
end

--- Whether `cmd` (a `cfg.cmd` table) already has its own `--query-driver=`
--- argument — from `options.servers.clangd` or a user's own override —
--- so `M.setup` never appends a second, conflicting one.
local function has_query_driver(cmd)
  for _, arg in ipairs(cmd) do
    if type(arg) == 'string' and arg:match('^%-%-query%-driver=') then
      return true
    end
  end
  return false
end

--- Configure mep.lsp (see mep.lsp.config.defaults for `enable`/
--- `servers`/`diagnostics`/`completion`/`keymaps`): registers every
--- server config, activates whichever `enable` selects *and* is found
--- on `PATH`, applies `vim.diagnostic.config`, and binds keymaps on
--- `LspAttach`. A no-op (with a warning) on Neovim < 0.11, where
--- `vim.lsp.config`/`vim.lsp.enable` don't exist yet.
function M.setup(opts)
  local options = config.setup(opts)

  -- Deliberately a version check, not a `type(vim.lsp.config) ==
  -- 'function'` feature-shape check: `vim.lsp.config` is actually a
  -- *table* with a `__call` metamethod (callable via `vim.lsp.config(name,
  -- cfg)` despite `type()` reporting `'table'`, confirmed empirically) —
  -- a naive type() check would misreport it as absent on every real
  -- Neovim version, not just old ones.
  if vim.fn.has('nvim-0.11') == 0 then
    vim.notify('mep.lsp: vim.lsp.config/vim.lsp.enable unavailable (needs Neovim 0.11+); skipping setup', vim.log.levels.WARN)
    return options
  end

  vim.diagnostic.config(options.diagnostics)

  local to_enable = {}
  for name, cfg in pairs(all_configs(options)) do
    -- Only for the stock clangd binary (a user who fully replaced cfg.cmd
    -- with something else is left alone) and only once (never duplicates
    -- a --query-driver the user already set themselves). Rebinds the
    -- loop-local `cfg` to a fresh, shallow-copied table rather than
    -- mutating fields on the original: `cfg` for a user-supplied
    -- `options.servers.clangd` entry is that caller's own table
    -- (`all_configs` only deep-copies the curated registry, not
    -- overrides), so writing into it in place would leak back into
    -- whatever config table they hold onto elsewhere.
    if name == 'clangd' and type(cfg.cmd) == 'table' and cfg.cmd[1] == 'clangd' and not has_query_driver(cfg.cmd) then
      local flag = query_driver_flag()
      if flag then
        cfg = vim.tbl_extend('force', cfg, { cmd = vim.list_extend(vim.deepcopy(cfg.cmd), { flag }) })
      end
    end
    vim.lsp.config(name, cfg)
    if should_enable(name, options.enable) and cmd_available(cfg) then
      to_enable[#to_enable + 1] = name
    end
  end
  if #to_enable > 0 then
    vim.lsp.enable(to_enable)
  end

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = vim.api.nvim_create_augroup('MepLsp', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        keymaps_mod.bind(args.buf, client, options.keymaps, options.completion)
      end
    end,
  })

  return options
end

return M

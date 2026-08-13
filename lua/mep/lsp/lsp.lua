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

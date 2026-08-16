--- Aggregator for mep's generic completion engine: pluggable sources
--- merged into Neovim's own native insert-mode completion popup
--- (`vim.fn.complete()`, via `mep.completion.engine`) — `<C-n>`/`<C-p>`
--- to navigate, `<C-y>` to accept, `<C-e>` to abort are all Neovim's own
--- built-in insert-mode completion keys, already there for free once
--- the engine populates the menu.
---
--- The LSP source (`mep.completion.sources.lsp`) needs no direct
--- coupling to `mep.lsp` specifically — it just queries whatever LSP
--- clients are attached via Neovim's own `vim.lsp.get_clients()`, which
--- any `mep.lsp`-started client is naturally part of. If you use both
--- libraries together, set `mep.lsp`'s own `completion = false` (its
--- native `vim.lsp.completion.enable` hookup) — otherwise two separate
--- completion triggers end up fighting over the same popup.
local config = require('mep.completion.config')
local engine = require('mep.completion.engine')

local M = {}
M.engine = engine

--- Registered sources, keyed by the name a `config.options.sources`
--- entry references. Each must expose `complete(ctx, callback(items))`
--- — see `mep.completion.sources.buffer`'s own header comment for the
--- fullest-documented example of the interface, or `.lsp`/`.path` for
--- an async one and a third built-in. Add your own by extending this
--- table with anything shaped the same way.
M.sources = {
  lsp = require('mep.completion.sources.lsp'),
  buffer = require('mep.completion.sources.buffer'),
  path = require('mep.completion.sources.path'),
  snippet = require('mep.completion.sources.snippet'),
}

--- Configure mep.completion (see mep.completion.config.defaults for
--- `sources`/`debounce_ms`/`min_chars`/`max_items`/`keymaps`) and start
--- listening for insert-mode typing. Warns (without erroring) about any
--- `sources` entry that isn't a registered name.
function M.setup(opts)
  local options = config.setup(opts)
  for _, name in ipairs(options.sources) do
    if not M.sources[name] then
      vim.notify('mep.completion: unknown source "' .. name .. '"', vim.log.levels.WARN)
    end
  end
  engine.enable()
  return options
end

return M

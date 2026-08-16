--- Aggregator for mep's native Debug Adapter Protocol client — no
--- external dap plugin dependency, mirroring how `mep.lsp` natively
--- drives `vim.lsp.config`/`vim.lsp.enable` instead of wrapping
--- lspconfig. `mep.dap.client`/`mep.dap.protocol` speak DAP over a
--- spawned adapter's own stdio; `mep.dap.session` is the single active
--- debug session built on top; `mep.dap.breakpoints`/`mep.dap.sidebar`/
--- `mep.dap.repl` are the editor-facing surface.
local config = require('mep.dap.config')
local adapters = require('mep.dap.adapters')
local breakpoints = require('mep.dap.breakpoints')
local session = require('mep.dap.session')
local sidebar = require('mep.dap.sidebar')
local repl = require('mep.dap.repl')
local keymaps = require('mep.dap.keymaps')

local M = {}
M.adapters = adapters
M.breakpoints = breakpoints
M.session = session
M.sidebar = sidebar
M.repl = repl

--- Configure mep.dap: extra/override `adapters`, gutter `signs`, and
--- global `keymaps` — see mep.dap.config.defaults. Binds `keymaps`
--- immediately (global, not buffer/attach-gated — debugging isn't
--- filetype-scoped the way LSP is). Works with sensible defaults even
--- if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  keymaps.bind(options.keymaps)
  return options
end

return M

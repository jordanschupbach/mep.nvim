--- Platform-agnostic system clipboard setup: turns on `'clipboard=
--- unnamedplus'` (see `mep.clipboard.config.defaults.unnamedplus`) and,
--- only when actually needed (SSH session, no local clipboard tool
--- reachable — see `mep.clipboard.platform`'s own header comment on
--- why Neovim's own native provider handles every *other* case
--- already), wires `vim.g.clipboard` to Neovim's own builtin OSC 52
--- provider (`vim.ui.clipboard.osc52`) so yank/paste still round-trips
--- through the terminal itself rather than silently doing nothing.
local config = require('mep.clipboard.config')
local platform = require('mep.clipboard.platform')

local M = {}
M.platform = platform

--- Build the `vim.g.clipboard` table (`:help g:clipboard`'s own shape)
--- from Neovim's builtin `vim.ui.clipboard.osc52` module — `copy`/
--- `paste` there are `function(reg) -> function(...)` factories, called
--- once per register here to get the plain functions `g:clipboard`
--- itself expects.
local function osc52_clipboard()
  local osc52 = require('vim.ui.clipboard.osc52')
  return {
    name = 'OSC 52',
    copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = osc52.paste('+'), ['*'] = osc52.paste('*') },
  }
end

--- Configure mep.clipboard: `enable`, `unnamedplus`, `osc52.enable`
--- (see mep.clipboard.config.defaults). `enable = false` is a full
--- no-op — `'clipboard'`/`vim.g.clipboard` stay exactly whatever they
--- already were.
function M.setup(opts)
  local options = config.setup(opts)
  if not options.enable then
    return options
  end

  if options.unnamedplus then
    vim.o.clipboard = 'unnamedplus'
  end

  if options.osc52.enable and platform.is_ssh() and not platform.has_local_tool() then
    vim.g.clipboard = osc52_clipboard()
  end

  return options
end

return M

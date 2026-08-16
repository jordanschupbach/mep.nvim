--- Neovim filetype -> `mep.org.babel.languages` key. Most filetypes
--- already match a babel key directly (`python` -> `python`, `lua` ->
--- `lua`, `go` -> `go`, `rust` -> `rust`, `ruby` -> `ruby`, ...) and
--- don't need an entry here at all — this table is only the handful
--- that differ.
local config = require('mep.run.config')

local M = {}

M.filetype_to_babel = {
  cs = 'csharp',
  bash = 'sh',
  cpp = 'cpp',
  ['c++'] = 'cpp',
  javascriptreact = 'javascript',
  typescriptreact = 'typescript',
  r = 'R',
}

--- The `mep.org.babel.languages` key for `filetype`: `config.options.
--- filetype_to_babel`'s own override if it has one, else `M.
--- filetype_to_babel`'s curated entry, else `filetype` itself
--- unmodified (the common case).
function M.resolve(filetype)
  return config.options.filetype_to_babel[filetype] or M.filetype_to_babel[filetype] or filetype
end

return M

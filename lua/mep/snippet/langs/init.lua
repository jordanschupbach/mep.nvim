--- `mep.snippet.config.defaults.builtin_langs`'s content: a curated
--- `{trigger, body}` set per filetype (Lua/Python/Go/Rust/C/JS/TS/
--- shell), each `mep.snippet.snippet`'s own `setup()` registers via
--- `mep.snippet.registry.add(filetype, ...)` when `builtin_langs` is
--- left on (the default). Not exhaustive per-language libraries — a
--- representative handful of idiomatic boilerplate/control-flow
--- entries each, same scope as any other single-file curated registry
--- in this project (e.g. `mep.lsp.servers`, `mep.dap.adapters`).
--- `javascript`/`typescript` and `sh`/`bash`/`zsh` share one snippet
--- set each (`langs/javascript.lua`/`langs/shell.lua`) since the
--- trigger words/bodies don't differ for plain usage.
local javascript = require('mep.snippet.langs.javascript')
local shell = require('mep.snippet.langs.shell')

return {
  lua = require('mep.snippet.langs.lua'),
  python = require('mep.snippet.langs.python'),
  go = require('mep.snippet.langs.go'),
  rust = require('mep.snippet.langs.rust'),
  c = require('mep.snippet.langs.c'),
  javascript = javascript,
  typescript = javascript,
  sh = shell,
  bash = shell,
  zsh = shell,
}

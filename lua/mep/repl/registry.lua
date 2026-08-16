--- Curated filetype -> REPL launch argv, BYO interpreter on PATH (same
--- "install it yourself" contract `mep.org.babel`'s own language table
--- documents) — a *separate* table from that one, deliberately: a REPL
--- launch command is a different program/flags than "run this script
--- file" (Python's REPL is a bare `python3` with no arguments at all,
--- not `python3 <file>`; bash/sh's REPL *is* an interactive shell
--- itself, not `bash <file>`). Only languages with a real, standard,
--- well-known interactive REPL are listed here — several `mep.org.
--- babel` supports for script execution (C/C++/Rust/Go/Java/Zig/Nim/
--- Crystal/D/Fortran/C#/Kotlin/Perl/...) have no comparably standard
--- interactive mode, and are deliberately left out rather than
--- guessing at one.
local M = {}

M.commands = {
  lua = { 'lua' },
  python = { 'python3' },
  javascript = { 'node' },
  -- No TypeScript-specific REPL assumed to be on PATH (ts-node isn't a
  -- standard install) — runs as plain JS, same as `javascript`.
  typescript = { 'node' },
  sh = { 'bash' },
  bash = { 'bash' },
  ruby = { 'irb' },
  r = { 'R', '--no-save' },
  julia = { 'julia' },
  clojure = { 'clj' },
  haskell = { 'ghci' },
  ocaml = { 'ocaml' },
  php = { 'php', '-a' },
  elixir = { 'iex' },
  scala = { 'scala' },
}

return M

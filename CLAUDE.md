# Instructions for agents working in this repo

## Always write unit tests

Whenever you implement a new feature or fix a bug in `lua/`, add or update
the corresponding busted spec under `spec/`, mirroring the module path
(`lua/mep/foo/bar.lua` -> `spec/mep/foo/bar_spec.lua`). This applies to
every change to plugin code, not just ones the user explicitly asks to be
tested. Run `just test` (or `busted` directly) before considering the work
done, and don't report a task complete with a red or untested suite.

Before writing a test that touches `vim.fn.jobstart` (directly or via
`mep.core.job`), read `spec/README.md` first — a real subprocess spawned
inside this test harness hangs the process at exit instead of failing.
Mock `vim.fn.jobstart` and drive its callbacks by hand instead; see
`spec/mep/core/job_spec.lua` or `spec/mep/picker/sources/grep_spec.lua` for
the pattern.

## Conventions to follow

- Each library lives at `lua/mep/<name>/` with an aggregator entry file of
  the same name (`<name>/<name>.lua`) that requires and wires together
  sibling implementation files, plus a thin `<name>/init.lua` shim
  (`return require('mep.<name>.<name>')`) so both `require('mep.<name>')`
  and `require('mep.<name>.<name>')` work. See `lua/mep/core/` for the
  reference example.
- A library that takes configuration owns a `<name>/config.lua` with
  `M.defaults`, `M.options`, and `M.setup(opts)` (deep-merge onto a fresh
  copy of the defaults — see `lua/mep/sanity/config.lua`), and exposes
  `M.setup(opts)` from its aggregator file. `require('mep').setup(opts)`
  fans `opts.<name>` out to each library's own `setup()`.
- Zero runtime dependencies: no plenary, no telescope, nothing outside
  Neovim's built-ins, at plugin *runtime*. Dev-only tooling (busted, nlua)
  is fine and lives outside `lua/`.
- Nothing should have a side effect just from being `require`d — behavior
  only happens once a library's `setup()` is called (or, for `mep.picker`,
  when one of its picker functions is invoked directly).

See `README.md` for the full architecture and `spec/README.md` for testing
details.

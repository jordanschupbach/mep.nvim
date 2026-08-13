# Tests

Unit tests run under [busted](https://lunarmodules.github.io/busted/),
configured (see `.busted`) to execute via
[`nlua`](https://github.com/mfussenegger/nlua) instead of plain Lua, so
`vim.*` is available to every spec — most of this codebase is `vim.api`/
`vim.fn`/`vim.uv` calls, and plain busted has no `vim` global at all.

Run the whole suite with `just test`, or directly with `busted` (optionally
pointed at one file or directory, e.g. `busted spec/mep/picker/`) from a
`nix develop` shell.

## The one thing nlua can't do: real subprocesses

`nlua` is a bare Lua interpreter linked against Neovim's `vim.*` bindings —
it is **not** a full running editor. Floating windows, buffers, autocmds,
timers, and the libuv threadpool (`vim.uv.new_work`, used by
`mep.core.parallel`) all work fine and exit cleanly. Real subprocesses
(`vim.fn.jobstart`, and therefore `mep.core.job`) do not: spawning a real
child process and letting it run to exit leaves the `nlua` process hanging
on exit, needing `SIGKILL`, even after the job has been explicitly stopped.
This was confirmed empirically while setting up this suite, not assumed —
plain timers and threadpool work were also suspected and turned out to be
fine.

Consequently:

- **`spec/mep/core/job_spec.lua`** tests `mep.core.job`'s real logic (line
  buffering across chunk boundaries, exit flushing, `kill()`, the
  failed-to-start path) by mocking `vim.fn.jobstart` itself and driving its
  callbacks by hand. No subprocess ever actually runs.
- **`spec/mep/picker/sources/files_spec.lua`** and **`grep_spec.lua`**
  (which both go through `core.job.spawn` to run `rg`) use the same
  `vim.fn.jobstart` mock, so the whole pipeline — source → `core.job` →
  `jobstart` — is exercised end-to-end, still without a real `rg` process.
- Nothing in this suite calls `core.job.spawn`/`vim.fn.jobstart` for real.
  End-to-end coverage of the actual `rg` integration (and of the full
  floating-window UI driven by real keystrokes) instead lives in the
  headless-`nvim` smoke test used during development — that runs inside a
  real editor instance, which manages subprocess lifecycles correctly.

If you add a test that needs a real external process, don't call
`core.job.spawn`/`jobstart` directly in a spec — mock `vim.fn.jobstart` the
same way the existing specs do.

## Writing a new spec

- Mirror `lua/mep/...` under `spec/mep/...spec.lua`.
- `spec/minimal_init.lua` (loaded automatically via `.busted`'s `helper`)
  just pins `vim.o.columns`/`vim.o.lines` for deterministic window-layout
  math; add shared bootstrapping there if a future spec needs it.
- To stub a module-level dependency (e.g. `mep.picker.preview`), save the
  original function, replace it, restore it after the assertion — modules
  are cached across the whole busted run, so a replacement left in place
  leaks into other spec files. See any `preview_mod.show_file = ...` usage
  in `spec/mep/picker/sources/` for the pattern.
- Clean up anything you open: close floating windows, `timer:stop();
  timer:close()` any uv timer you create directly. Picker instances should
  be closed in an `after_each` (see `engine_spec.lua`) both for isolation
  and because leaked handles are exactly the kind of thing that can trigger
  the exit-hang behaviour described above.
- **If your `setup()` registers a real autocmd**, delete its augroup by
  name in `after_each` (`pcall(vim.api.nvim_del_augroup_by_id/by_name,
  ...)`) — don't assume a later `setup()` call recreating the group with
  `clear = true` is enough cleanup. Every spec file runs in the same
  editor session, so an autocmd left registered (e.g. a `FileType`
  autocmd) fires for *any* buffer any later spec — in any file — gives a
  matching filetype to. This caused two real cross-file failures while
  building `mep.treesitter`/`mep.org` (see git history around those
  specs): a stale `MepTreesitter` `FileType` autocmd made an unrelated
  `activate_spec.lua` test see highlighting it never asked for. Also
  clean up any buffer your test leaves with a distinguishing filetype set
  (`nvim_create_buf` here doesn't wipe on its own) — a later `setup()`
  call's "activate already-loaded buffers" pass will find it otherwise.
- Cosmetic-only: running certain spec-file combinations together (but not
  in isolation) can print a stray `E211: File "..." no longer available`
  and add roughly a second to the run — this doesn't fail anything and
  wasn't tracked down to a specific cause (harmless global buffer/autocmd
  state accumulating across many spec files sharing one editor session,
  not present in real usage). If you see it, don't panic — check the
  actual pass/fail count first.

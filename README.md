# mep.nvim

A zero-dependency Neovim plugin/distribution using a modular architecture of
a collection of independent Lua libraries under one repo. No `plenary`, no
`telescope`, no external Lua deps — only Neovim's built-in APIs plus, where a
library chooses to shell out, standard CLI tools (currently: `rg`,
optionally `git` + a C compiler for `mep.treesitter`'s parser installer, and
`curl` for `mep.ai`'s own LLM streaming — only needed if you actually use
that library).

Each library has a directory named after itself, with a single entry file
of the same name that aggregates the pieces implemented in sibling files —
e.g. `lua/mep/core/core.lua` aggregates `coroutines.lua`, `job.lua`,
`parallel.lua`, `util.lua`. A thin `init.lua` shim in each directory just
does `return require('mep.<name>.<name>')`, so both `require('mep.core')`
and `require('mep.core.core')` work.

## Libraries

### `mep.core` — async/parallel building blocks

- **`core.coroutines`** — minimal async/await on native Lua coroutines
  (`wrap`, `await`, `run`, `async`). Turn any callback-style API into
  something you can write as straight-line code.
- **`core.job`** — async external-process runner on top of
  `vim.fn.jobstart`, streaming stdout/stderr line-by-line.
- **`core.parallel`** — *real* parallelism via libuv's threadpool
  (`vim.uv.new_work`): `parallel.map(items, work_fn, on_done)` runs
  `work_fn` on worker OS threads. Note libuv's constraint: `work_fn` runs in
  an isolated Lua state, so it can't close over locals or call `vim.*` —
  only pure computation on its arguments.
- **`core.util`** — `debounce`, `find_root` (nearest ancestor with `.git`),
  `scan_dir` (synchronous recursive file listing fallback).

### `mep.sanity` — sane Neovim defaults

A small, growing set of opinionated-but-overridable defaults, each one
independently configurable and individually disableable (set its option to
`false`). Currently:

- **leader** (`mep.sanity.leader`) — sets `mapleader`/`maplocalleader`.
  Default: `' '` (space).
- **tabs** (`mep.sanity.tabs`) — tab keymaps. Default: `<C-t>` (`:tabnew`),
  `<Mod1-1>`..`<Mod1-9>` (`Mod1` = Alt on Linux/Windows, Option on macOS —
  see [Global modifier keys](#global-modifier-keys) under Setup; jump
  straight to tab 1-9, `:tabnext {n}`) — not
  `<C-Tab>`/`<C-S-Tab>`-style cycling, since most terminals don't send a
  distinguishable code for Ctrl+Tab/Ctrl+Shift+Tab at all (Alt+digit is
  much more reliably passed through).
- **number**/**signcolumn** (`mep.sanity.gutter`) — turns on line numbers
  (`'number'`) and the sign column (`'signcolumn' = 'yes'`, always shown
  rather than the default `'auto'` which only appears once something
  places a sign — keeps the text column from shifting when the first
  sign shows up). Both default to `true`; set either to `false` to leave
  Neovim's own default (`number` off, `signcolumn` `'auto'`) alone.
  Global options, so they don't need per-buffer wiring — `mep.dashboard`
  separately suppresses both in its own window regardless of this
  setting (`mep.dashboard.ui.prepare_window`), so the startup screen
  stays gutter-free either way.

```lua
require('mep.sanity').setup({}) -- leader = ' ', tabs.keymaps = { new = { '<C-t>' }, select = { '<Mod1-1>', ..., '<Mod1-9>' } }, number = true, signcolumn = true
require('mep.sanity').setup({ leader = ',' }) -- leader = ','
require('mep.sanity').setup({ leader = false }) -- don't touch mapleader at all
require('mep.sanity').setup({ tabs = { keymaps = { new = { '<leader>tn' } } } }) -- override just one action
require('mep.sanity').setup({ tabs = { keymaps = false } }) -- don't bind any tab keymaps
```

Like every mep library, nothing here applies just from `require`ing it —
only `setup()` has effect.

### `mep.dashboard` — a startup dashboard, in place of Neovim's own intro

Takes over the initial empty buffer at startup — same trigger conditions
as Neovim's own `:intro` screen (no file arguments, a single untouched
empty buffer, one window, no piped stdin) — and renders content into it
instead.

By default that content is a constructed recreation of Neovim's own intro
message, with a block-character logo (`mep.dashboard.content.LOGO`) above
`NVIM vX.Y.Z` and an `MEP vX.Y.Z` line under it. Worth knowing: none of
this is captured from Neovim — `:intro` is drawn directly onto the screen
grid, bypassing the message/echo history entirely, so
`vim.fn.execute('intro')` reliably returns `''` and there's no Lua API
that can pull the literal live text or any logo (checked by scanning the
actual compiled Neovim binary's embedded strings — there's no ASCII art
in there to find, even on current nightlies). `mep.dashboard.content`
reproduces the message's stable wording by hand and adds the logo as an
original touch, with the Neovim version (and the "news" help-tag) always
computed live from `vim.version()`, and the mep version read from
`mep.version` — the plugin's own single source of truth for its version
number, also reachable as `require('mep').version` — so neither ever
goes stale relative to the other.

```lua
require('mep.dashboard').setup({}) -- auto_open = true, content = 'intro' (the default)
require('mep.dashboard').setup({ content = { 'Welcome!', '', ':MepFindFiles to start' } })
require('mep.dashboard').setup({ content = function() return {...} end })
require('mep.dashboard').setup({ auto_open = false }) -- disable the automatic takeover
```

`:MepDashboard` / `require('mep.dashboard').open()` shows it manually (in
the current window) any time. Content is centered both horizontally (each
line individually) and vertically within the window. The window's own
gutter — `number`/`relativenumber`/`signcolumn`, plus the `~` end-of-
buffer filler past the centered content — is turned off for as long as
that window keeps showing the dashboard, window-local (`vim.wo`, not
`vim.o`) so nothing else is affected; the moment something replaces the
dashboard buffer there (e.g. opening a real file over it), its previous
values come back automatically, in that same window.

Rendering applies a small pattern-based highlight scheme (not a captured
original — see above — a deliberately-designed one): the logo and version
lines (`NVIM vX.Y.Z` / `MEP vX.Y.Z`) get top billing, URLs are underlined,
and `:command<Enter>` hints get their own color. It runs on whatever
`content` resolves to, so a custom line that happens to contain a URL, a
`:cmd<Enter>`, or a run of block characters still picks it up.

#### Highlight groups

- `MepDashboardLogo` — the block-character logo (links to `Title`)
- `MepDashboardVersion` — the `NVIM vX.Y.Z` / `MEP vX.Y.Z` lines (links to `Title`)
- `MepDashboardCommand` — `:command<Enter>` hints (links to `Special`)
- `MepDashboardLink` — URLs (links to `Underlined`)

### `mep.scratch` — a single, persistent throwaway notepad buffer

`:MepScratch` / `require('mep.scratch').open()` switches the current
window to a scratch buffer, creating it the first time it's called.
Unlike `:enew`'s own buffer (unnamed, and wiped the moment you switch
away from it if `'hidden'` is off), this one is real (`buftype=nofile`,
`swapfile=false` — never actually touches disk) but reused across every
`open()` call in the session (`bufhidden=hide`, not `'wipe'`), so its
content survives switching away and back — splitting it, closing the
window, or navigating to another buffer and back all behave exactly like
any other buffer.

```lua
require('mep.scratch').setup({}) -- name='scratch', filetype=''
require('mep.scratch').setup({ filetype = 'markdown' }) -- basic syntax highlighting while jotting notes
```

`require('mep.scratch').reset()` discards the current scratch buffer (and
its content) so the next `open()` starts fresh with a brand new one.

### `mep.icons` — file/directory icons, no special font required

Looks up an icon glyph for a file (by exact basename, then by lowercased
extension, falling back to a generic file icon) or a directory
(closed/open variants), plus a matching tree-expand marker. Three styles:

- **`nerd_font`** (default) — monochrome [Nerd Font](https://www.nerdfonts.com/)
  glyphs with real per-language differentiation (Lua, Python, JS/TS/JSX/TSX,
  Go, Rust, Ruby, Java, C/C++, C#, PHP, shell variants, web/data formats,
  and more each get their own glyph). The codepoints are the same ones
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) ships
  as its own defaults — pulled from that project's own default-icon tables,
  not hand-picked from memory — so they're a widely-deployed, known-good
  set. Only looks right with a Nerd Font actually installed and selected in
  your terminal/GUI; set `style = 'emoji'` if you don't have one.
- **`emoji`** — standard Unicode emoji covering ~40 common extensions and a
  few special filenames (`Makefile`, `.gitignore`, ...). Renders correctly
  everywhere; no font installation needed.
- **`ascii`** — plain 7-bit fallback, no per-type icons at all, for
  terminals with poor Unicode support.

```lua
require('mep.icons').setup({ style = 'emoji' }) -- opt back out of nerd_font
require('mep.icons').get_file_icon('main.lua')       --> icon, 'MepIconFile'
require('mep.icons').get_directory_icon(true)         --> open-folder icon, 'MepIconDirectory'
```

Layer your own icons on top of (or instead of) the built-ins per style via
`overrides`, e.g. `overrides = { emoji = { by_extension = { lua = '🌛' } } }`
— see `lua/mep/icons/data.lua` for the full built-in tables.

A small curated **"UI action" icon set** — bell/checkmark/play/branch/
plus/trash, keyed by semantic name (`notifications`/`todo`/`tests`/
`git`/`add`/`clear`) rather than glyph shape — sits alongside the file/
directory tables, for callers that need a small fixed icon rather than
one keyed by file content: `mep.activitybar`'s own bar buttons and todo/
tests panel actions use it (`require('mep.icons').get_ui_icon('git')`),
so they respect `setup({ style = ... })` the same way file icons do.
These are already plain, universally-renderable symbols rather than
font-dependent glyphs, so `nerd_font` and `emoji` share the same set;
only `ascii` meaningfully differs.

### `mep.filetree` — a file tree sidebar, using mep.icons

`mep.filetree` has no icon-style option of its own — it always renders
through the shared `mep.icons` module above, so its default icon style
(and any `overrides`) come from `require('mep.icons').setup({...})`.

A single persistent tree panel (a real vertical split, not a floating
window — it should behave like a normal window in your layout) backed by
lazy, one-level-at-a-time directory scanning, so opening it on a huge
project doesn't walk the whole filesystem up front.

| Command                | Lua API                              | What it does                        |
|-------------------------|----------------------------------------|--------------------------------------|
| `:MepFileTreeToggle`    | `require('mep.filetree').toggle()`     | Open/close the tree                  |
| `:MepFileTreeRefresh`   | `require('mep.filetree').refresh()`    | Re-scan expanded directories in place |

`toggle()`/`open()` accept an optional `{ root = ... }`, defaulting to
`mep.filetree.config.options.root` and then `core.util.find_root()`.

#### Keymaps inside the tree (normal mode)

| Key            | Action                                                        |
|-----------------|----------------------------------------------------------------|
| `<CR>` / `o`    | Open file under cursor (in the window the tree was opened from), or toggle a directory |
| `<C-o>`         | Open the file/directory under cursor with the OS's own default program (`vim.ui.open` — `xdg-open` on Linux, `open` on macOS), not Neovim |
| `l` / `<Right>` | Expand directory under cursor                                  |
| `h` / `<Left>`  | Collapse an expanded directory, or jump to its parent            |
| `q` / `<Esc>`   | Close the tree                                                  |
| `R`             | Refresh                                                          |
| `a`             | Create a file/directory (prompts for a name relative to the node under the cursor; trailing `/` makes a directory) |
| `r`             | Rename the file/directory under the cursor (prompts, pre-filled with its current name) |
| `d`             | Delete the file/directory under the cursor (confirms first; directories are removed recursively) |
| `?`             | Toggle a popup listing every keymap above (dismiss with `q`/`<Esc>`/`?`) |

A horizontal rule and a "Press ? for help" hint sit below the tree
itself, at the bottom of the panel.

All configurable via `require('mep.filetree').setup({...})` —
`width`, `root`, `show_hidden`, and `keymaps.open`/`open_system`/`expand`/`collapse`/`close`/`refresh`/`add`/`rename`/`delete`/`help`
(each a list of lhs strings). See `lua/mep/filetree/config.lua` for the
full defaults.

#### Highlight groups

- `MepIconFile` — file icons (links to `Normal`)
- `MepIconDirectory` — directory icons (links to `Directory`)
- `MepFiletreeDirectory` — directory names in the tree (links to `Directory`)

### `mep.symbols` — an LSP-backed symbols outline

A single persistent panel (like `mep.filetree`, only one at a time)
showing whatever the client attached to the current buffer reports for
`textDocument/documentSymbol` — classes, methods, functions, variables,
enums, and so on, filetype-specific purely because that's whatever the
attached server understands for that filetype (no client attached, or
one that doesn't support the method, shows a message instead of erroring).

Unlike `mep.filetree`'s tabpage-edge-anchored tree, this one splits the
*current* window itself (`<leader>ll` by default) — sized to
`config.options.width_ratio` (a quarter, by default) of that window's
width, on the right — since it's tied to one specific buffer's symbols,
not a project-wide view. `<CR>` on a symbol jumps to it in the buffer
the outline was opened for; `R` re-requests symbols on demand, and a
`BufWritePost` on that buffer does the same automatically.

| Command               | Lua API                              | What it does                            |
|-------------------------|-----------------------------------------|--------------------------------------------|
| `:MepSymbolsToggle`   | `require('mep.symbols').toggle()`    | Open/close the outline for the current buffer |
| `:MepSymbolsRefresh`  | `require('mep.symbols').refresh()`   | Re-request symbols for the open outline |

#### Keymaps inside the outline (normal mode)

| Key            | Action                                          |
|-----------------|--------------------------------------------------|
| `<CR>`          | Jump to the symbol under the cursor               |
| `q` / `<Esc>`   | Close the outline                                 |
| `R`             | Refresh                                            |

All configurable via `require('mep.symbols').setup({...})` —
`width_ratio`, `min_width`, `position` (`'left'`/`'right'`),
`keymaps.jump`/`close`/`refresh`, and `triggers.toggle` (the global
`<leader>ll` keymap, bound outside the panel itself — `mep.picker`'s
own `triggers` pattern). See `lua/mep/symbols/config.lua` for the full
defaults.

```lua
require('mep.symbols').setup({}) -- width_ratio=0.25, min_width=20, position='right', triggers.toggle={'<leader>ll'}
require('mep.symbols').setup({ position = 'left', width_ratio = 0.3 })
require('mep.symbols').setup({ triggers = { toggle = { '<leader>o' } } }) -- rebind the global toggle
```

#### Highlight groups

- `MepSymbolsTitle` — the outline's winbar title (links to `Title`)
- `MepSymbolsKind` — the `[KindName]` tag on each symbol line (links to `Comment`)

### `mep.hints` — jump-to-location hints, hop.nvim/flash.nvim-style

A pure Lua overlay (extmarks, no external dependency) that labels
locations in the current window's visible lines and jumps the cursor
there once you type the label — real editing, not an LSP inlay hint or a
static cheatsheet. Two modes:

- **`require('mep.hints').char_search()`** — prompts (blocking) for one
  character, then labels every occurrence of it visible in the current
  window.
- **`require('mep.hints').word_start()`** — labels every visible word
  start immediately, no prompt.

Either way: zero matches just notifies; exactly one jumps straight there
with no label shown at all; more than one overlays a label (drawn from
`config.options.labels`, home-row order by default) on top of each
match's own first column(s) — single characters while the match count
fits the charset, two-character combinations beyond that (never mixed,
so a pressed key is never ambiguous between a whole label and half of a
longer one). `<Esc>`/`<C-c>`, or any key that matches no label, cancels
cleanly with no jump.

```lua
require('mep.hints').setup({}) -- labels='asdfghjklqwertyuiopzxcvbnm', triggers.char/word unbound
require('mep.hints').setup({ triggers = { char = { 's' }, word = { 'w' } } }) -- hop.nvim's own bindings
require('mep.hints').setup({ labels = 'abcdefghijklmnopqrstuvwxyz' }) -- alphabetical instead of home-row
```

Both `triggers.char`/`triggers.word` are unbound by default (`false`/an
empty list) — mep.picker's own `triggers` pattern — since there's no
single obvious default keymap to claim for either mode.

#### Highlight groups

- `MepHintMatch` — the matched span underneath a label (links to `Search`)
- `MepHintLabel` — the label glyph(s) overlaid on top of the match (links to `ErrorMsg`)

### `mep.dap` — a native Debug Adapter Protocol client

No external `nvim-dap` dependency — `mep.dap.client`/`mep.dap.protocol`
speak DAP directly (`Content-Length`-framed JSON, the same base protocol
LSP itself uses) over a spawned adapter process' own stdio, the same
"drive the real protocol natively" posture `mep.lsp` already takes with
`vim.lsp.config`/`vim.lsp.enable` instead of wrapping lspconfig.

- **`mep.dap.adapters`** — a curated registry (`debugpy`/`lldb_dap`/
  `netcoredbg`/`delve`, `{ cmd, filetypes }` shaped like `mep.lsp.servers.
  registry`) of common adapters. **Unlike** that LSP registry, these
  `cmd`s are each adapter's documented stdio invocation, not
  independently verified against a live install — DAP adapters are far
  less standardized about transport than language servers (most were
  built for VS Code's own socket-based extension host). Treat `cmd` as a
  starting point; override per-adapter via `adapters = { <name> = { cmd =
  {...} } }`. Adapter binaries are BYO, same install-it-yourself contract
  as `mep.lsp`'s own servers.
- **`mep.dap.breakpoints`** — session-only (not persisted), keyed by
  absolute file path so a breakpoint set once reappears in any buffer
  that later reopens the same file. `toggle(bufnr, lnum)`/`list(bufnr)`/
  `clear(bufnr)`/`clear_all()`; sign-column gutter (`MepDapBreakpoint`),
  `attach(bufnr)`/`detach(bufnr)` re-render it on `BufReadPost`.
- **`mep.dap.session`** — the single active session (only one debuggee at
  a time, like `mep.ai`'s single in-flight job): `launch(adapter_name,
  args)`/`attach(adapter_name, args)` run the full DAP handshake
  (`initialize` -> `launch`/`attach` -> wait for the adapter's own
  `initialized` event -> push every recorded breakpoint via
  `setBreakpoints` -> `configurationDone`); `launch_interactive()`
  prompts (`vim.ui.select`/`vim.ui.input`) for both. `continue`/
  `step_over`/`step_into`/`step_out`/`terminate`/`evaluate(expression,
  callback)` control it; a `stopped` event fetches the call stack, the
  top frame's scopes and their variables, and jumps the editor there
  (`MepDapStopped` sign). `subscribe(fn)` hears every change
  (`'stopped'`/`'output'`/`'stack_updated'`/...) — what `mep.dap.sidebar`/
  `mep.dap.repl` render from.
- **`mep.dap.sidebar`** — a `mep.sidebar`-built panel (call stack /
  scopes+variables / breakpoints), redrawing itself on `mep.dap.session.
  subscribe` and `mep.dap.breakpoints.on_change`.
- **`mep.dap.repl`** — a persistent console buffer accumulating the
  adapter's own `output` events; `evaluate_interactive()` prompts for an
  expression and appends both it and its result.

```lua
require('mep.dap').setup({}) -- keymaps.toggle_breakpoint=<leader>db, continue=<leader>dc, ...
require('mep.dap').setup({ adapters = { debugpy = { cmd = { 'python', '-m', 'debugpy.adapter' } } } })
require('mep.dap').session.launch('debugpy', { program = '/path/to/script.py' })
```

| Command                    | Lua API                                     | What it does                            |
|------------------------------|------------------------------------------------|--------------------------------------------|
| `:MepDapToggleBreakpoint`  | `require('mep.dap').breakpoints.toggle(...)`  | Toggle a breakpoint on the current line   |
| `:MepDapLaunch`            | `require('mep.dap').session.launch_interactive()` | Start a session (prompts for adapter + program) |
| `:MepDapContinue`          | `require('mep.dap').session.continue()`       | Continue the active session               |
| `:MepDapTerminate`         | `require('mep.dap').session.terminate()`      | Terminate the active session              |
| `:MepDapSidebar`           | `require('mep.dap').sidebar.toggle()`         | Toggle the debug sidebar                  |
| `:MepDapRepl`              | `require('mep.dap').repl.toggle()`            | Toggle the debug console                  |

#### Highlight groups

- `MepDapBreakpoint` — the breakpoint gutter sign (links to `DiagnosticError`)
- `MepDapStopped` — the current-line sign where execution is paused (links to `DiagnosticWarn`)
- `MepDapReplTitle` — the debug console's winbar title (links to `Title`)

### `mep.docs` — docstring generation and external doc lookup

- **`mep.docs.generate`** (`<leader>ld` by default) — inserts a language-
  appropriate doc-comment skeleton for the function on the cursor line.
  Tries `mep.docs.lsp` first (a real `textDocument/signatureHelp`
  request — the same one `mep.lsp`'s own `<C-k>` makes — parsed into a
  plain function name and parameter list) when a capable client is
  attached; falls back to `mep.docs.parser`'s own single-line regex scan
  of the cursor's line otherwise. Curated for `python`/`lua`/`go`/`rust`/
  `ruby`/`javascript`/`typescript`(`react` variants)/`c`/`cpp`/`java`
  (`mep.docs.templates.docstring`) — Google-style for Python, LDoc/
  EmmyLua (`---@param`) for Lua, rustdoc, YARD, godoc's own bare-summary
  convention, and JSDoc/Doxygen/Javadoc sharing one `/** ... */` shape.
  `'below'`-position languages (Python) nest one level deeper than the
  function line, matching `'expandtab'`/`'shiftwidth'`; `'above'`-
  position ones share its own indentation.
- **`mep.docs.lookup`** (`<leader>lD` by default) — opens external
  documentation for the word under the cursor via `mep.url.open` (`vim.
  ui.open`, no in-editor scraping/fetching): a devdocs.io instant-search
  deep link (`https://devdocs.io/#q=...`), biased toward the right doc
  set via a per-filetype hint (`mep.docs.templates.doc_hints`) when one's
  curated — **not** a verified devdocs slug/scoping syntax (same caveat
  `mep.dap.adapters`'s own header comment documents for its `cmd`s), just
  the doc set's own display name, which devdocs' search already matches
  loosely; a filetype with no entry still gets a working, if unscoped,
  search.

```lua
require('mep.docs').setup({}) -- keymaps.generate=<leader>ld, lookup=<leader>lD
require('mep.docs').setup({ doc_hints = { python = 'python~3.13' } }) -- pin a devdocs version slug
```

| Command                | Lua API                          | What it does                                    |
|--------------------------|-------------------------------------|------------------------------------------------------|
| `:MepDocsGenerate`     | `require('mep.docs').generate()` | Insert a docstring skeleton for the current function  |
| `:MepDocsLookup`       | `require('mep.docs').lookup()`   | Open external docs for the word under cursor          |

### `mep.flashcards` — spaced-repetition review, org-drill style

Review sessions over org headlines tagged `config.options.tag` (`:drill:`
by default, inheritance-aware — a headline under a `:drill:`-tagged
parent counts too, `mep.org.tags.effective_tags`), collected across
`config.options.drill_files` (`mep.flashcards.collect`, the exact same
literal-path/glob-pattern shape `mep.org.agenda`'s own `agenda_files`
uses — this library reuses `mep.org.agenda.files` itself to resolve
them).

- **Scheduling** (`mep.flashcards.sm2`) — the classic SM-2 algorithm
  (Wozniak, 1987; the same core Anki and real org-drill both build on),
  a 4-button grade vocabulary (again/hard/good/easy, mapped onto SM-2's
  own 0-5 quality scale) rather than the full 6-point one. State (`:
  DRILL_EF:`/`:DRILL_REPS:`/`:DRILL_INTERVAL:`/`:DRILL_DUE:`) lives in
  the headline's own `:PROPERTIES:` drawer via `mep.org.property`
  (`mep.flashcards.state`) — reusing that existing store rather than a
  separate one, and buffer-only like every other write this project
  makes to your files (`mep.org.agenda`'s own TODO-cycle keymap
  included) — your own save workflow persists it.
- **Review UI** (`mep.flashcards.review`, `:MepFlashcardsReview` /
  `require('mep.flashcards').review_session()`, default `<leader>fr`) —
  one card at a time in a floating popup: the headline title as the
  question, `<CR>`/`<Space>` reveals the body as the answer (`mep.
  flashcards.body`, everything up to the next headline at any level, so
  a child headline's own content isn't pulled in as part of this card's
  answer), then `a`/`h`/`g`/`e` grades it and advances. A no-op (with a
  notification) when nothing's due.

```lua
require('mep.flashcards').setup({ drill_files = { '~/notes/*.org' } })
require('mep.flashcards').setup({ tag = 'flashcard' }) -- use :flashcard: instead of :drill:
```

```org
* Capital of France? :drill:
Paris.
```

### `mep.help` — a generated vimdoc, plus a searchable command/keymap/docs picker

Two independent pieces:

- **`doc/mep.txt`** — a real Neovim vimdoc, condensed from this README's
  own per-library sections, with a `*mep-<name>*` tag per library
  (`*mep-hints*`, `*mep-dap*`, ...) so `:help mep` / `:help mep-symbols`
  work through Neovim's native help system. Run `:helptags` on this
  repo's own `doc/` directory once after installing if your plugin
  manager doesn't do that automatically (most do).
- **`mep.help.picker`** (`:MepHelp` / `require('mep.help').picker()`,
  default `<leader>?`) — a `mep.picker`-backed searchable index over
  three existing sources, not a separate store: every curated library's
  one-line description (`mep.help.descriptions`, `<CR>` opens its
  `:help` tag), every visible Ex command (`mep.picker.sources.commands`,
  `<CR>` runs it, prompting for args first if it takes any), and every
  visible normal-mode keymap (`mep.whichkey.registry`, `<CR>` executes
  it exactly as if pressed — `mep.whichkey`'s own dispatch, real Neovim
  built-ins aren't included since `nvim_get_keymap` only ever reports
  user-defined mappings).

```lua
require('mep.help').setup({}) -- keymaps.picker=<leader>?
require('mep.help').setup({ descriptions = { my_lib = { desc = 'my own library', tag = 'my-lib' } } })
```

### `mep.colorizer` — highlight colors, in any buffer

Detects `#rgb`/`#rrggbb`/`#rrggbbaa`, `rgb()`/`rgba()`, and the full
standard CSS named-color list (`mep.colorizer.names`, from MDN's own
reference table) in any buffer, rendering either a background swatch
over the matched text (foreground auto-picked black/white for contrast,
perceived-brightness heuristic) or an inline swatch character just
before it — extmarks, same overlay technique `mep.markdown.tables` uses
for its own cell borders. Attach/detach lifecycle (debounced recompute
on `TextChanged`/`TextChangedI`/`BufWritePost`) mirrors `mep.markdown.
gutter`'s own; the global auto-attach-by-filetype wiring mirrors `mep.
git.gutter`'s own `enable()`/`disable()`.

```lua
require('mep.colorizer').setup({}) -- mode='background', every filetype
require('mep.colorizer').setup({ mode = 'swatch' }) -- ● before each match instead
require('mep.colorizer').setup({ filetypes = { 'css', 'html', 'lua' } }) -- restrict where it activates
```

### `mep.leetcode` — local problem execution, plus opt-in live submission

Local problem files (`.org`, one per problem, under `config.options.
problems_dir`): `#+TITLE:`/`#+PROPERTY: LEETCODE_SLUG ...`/`#+PROPERTY:
LEETCODE_DIFFICULTY ...` file keywords, a `* Prompt` headline, a
`* Solution` headline with the editable src block (the file's *first* src
block), and a `* Tests` headline with one src block per sample test (every
block *after* the first). `mep.leetcode.picker` (`:MepLeetcode` /
`require('mep.leetcode').picker()`, default `<leader>lc`) browses/opens
them.

- **Running tests** (`:MepLeetcodeRunTests` / `require('mep.leetcode').
  run_tests()`) splices the Solution block's body above each Test
  block's own body into one combined src block in a throwaway scratch
  buffer, then runs it through `mep.org.babel.execute` itself — the same
  language dispatch (interpreter/compiler resolution, compile-then-run,
  `wrap_main`, ...) real org-babel execution already goes through, not a
  separate implementation of it. Pass/fail is left entirely to whatever
  the test code itself prints (a boolean comparison, an assertion,
  `"Test 1: PASS"`, ...) — notified per test as raw output, plus a final
  summary.
- **Live mode** (opt-in, network calls only from these two actions) —
  `:MepLeetcodeFetch` / `require('mep.leetcode').fetch_interactive()`
  fetches a problem's statement/starter code by its URL slug and writes
  it as a new local file; `:MepLeetcodeSubmit` / `require('mep.leetcode').
  submit()` submits the current file's Solution block and polls for a
  verdict. Both go through LeetCode's own unofficial (reverse-engineered
  — the query/endpoint shapes community tools like leetcode-cli use, not
  independently verified against a live account from this project's own
  dev environment) GraphQL + REST API, via real `curl` subprocesses
  (`mep.leetcode.api`, the same job-running idiom `mep.ai`'s own request
  path uses). Credentials are two browser cookie values from a
  logged-in LeetCode session (`LEETCODE_SESSION`/`csrftoken`, copied out
  of your browser's devtools), read from environment variables
  (`config.options.session_cookie_env`/`csrf_token_env`) — never
  hardcoded.

```lua
require('mep.leetcode').setup({}) -- problems_dir=stdpath('data')/mep_leetcode, default_language='python'
require('mep.leetcode').setup({ default_language = 'go' })
```

| Command                  | Lua API                                        | What it does                              |
|-----------------------------|----------------------------------------------------|------------------------------------------------|
| `:MepLeetcode`           | `require('mep.leetcode').picker()`             | Browse/open local problems                |
| `:MepLeetcodeRunTests`   | `require('mep.leetcode').run_tests()`          | Run sample tests for the current problem  |
| `:MepLeetcodeFetch`      | `require('mep.leetcode').fetch_interactive()`  | Fetch a problem (live mode) into a new local file |
| `:MepLeetcodeSubmit`     | `require('mep.leetcode').submit()`             | Submit the current Solution block (live mode) |

### `mep.roam` — org-roam-style note linking

Zettelkasten-style notes over plain org headlines — no separate ID/link
mechanism: every piece below builds on `mep.org.id.get_or_create` (a
note's own first headline gets a stable `:ID:` property, generated the
first time anything needs it) and `mep.org.link` (`[[id:...][title]]`,
this project's own existing link syntax).

- **`mep.roam.picker`** (`:MepRoamInsert` / `require('mep.roam').
  picker()`, default `<leader>rf`) — fuzzy search note titles
  (`#+TITLE:`, or the first headline's own title) across `config.
  options.roam_dirs` (recursively), `<CR>` inserts a `[[id:...][title]]`
  link at the cursor.
- **`mep.roam.backlinks`** (`:MepRoamBacklinks` / `require('mep.roam').
  toggle_backlinks()`, default `<leader>rb`) — a `mep.sidebar` panel
  (like `mep.symbols`' own single-instance outline) listing every note
  that links to the current note's own ID; `<CR>` on an entry jumps to
  the linking headline.
- **`mep.roam.daily`** (`:MepRoamToday` / `require('mep.roam').today()`,
  default `<leader>rt`) — opens (creating if missing)
  `roam_dirs[1]/daily/YYYY-MM-DD.org`, an existing file opened as-is;
  a new one's initial content comes from `config.options.daily_template`
  (`mep.org.capture`'s own placeholder syntax — `%T`/`%?`/`%^{PROMPT}`/
  ..., reused directly rather than a separate templating mechanism).
- **`mep.roam.create`** (`:MepRoamNew` / `require('mep.roam').
  new_note()`, default `<leader>rc`) — prompts for a title, creates
  `roam_dirs[1]/<slugified-title>.org` with a `* <title>` headline and a
  fresh `:ID:` already attached.

```lua
require('mep.roam').setup({ roam_dirs = { '~/notes/roam' } })
require('mep.roam').setup({ daily_template = '#+TITLE: %T\n\n* Log\n%?' })
```

| Command              | Lua API                              | What it does                       |
|-------------------------|------------------------------------------|-----------------------------------------|
| `:MepRoamInsert`     | `require('mep.roam').picker()`         | Search notes, insert a link to one |
| `:MepRoamBacklinks`  | `require('mep.roam').toggle_backlinks()` | Toggle the backlinks panel         |
| `:MepRoamToday`      | `require('mep.roam').today()`          | Open (or create) today's daily note |
| `:MepRoamNew`        | `require('mep.roam').new_note()`       | Create a new note (prompts for a title) |

### `mep.run` — a play button: run the current file

`:MepRun` / `require('mep.run').run_current_file()` (default `<leader>xr`)
runs the current buffer's own file through its filetype's own
interpreter/compiler, output going to a real `:terminal` split
(`mep.project`'s own terminal-split usage as precedent) — reusing `mep.
org.babel`'s existing per-language resolution (`resolve_executable`/
`run_cmd`/`compile_cmd`/`run_compiled_cmd`) rather than a separate
interpreter table, most Neovim filetypes already matching a babel
language key directly (`python` -> `python`, `go` -> `go`, ...; `mep.run.
languages` covers the handful that don't, e.g. `cs` -> `csharp`). Unlike
`mep.org.babel.execute` (which runs a *copy* of a src block's body, with
`:main yes` able to wrap bare statements), this runs the file exactly as
it already is on disk — a play button presumes a complete, already-
runnable program.

`require('mep.run').widget()` is a `mep.chrome`-widget-shaped table
(`{ text, on_click }`) for a clickable ▶ button — `mep.chrome` and
`mep.run` are independent libraries, composed only via config, like
every other pairing in this project:

```lua
require('mep.run').setup({}) -- terminal_height_ratio=0.3, keymaps.run=<leader>xr
require('mep.chrome').setup({ winbar = { widgets = { require('mep.run').widget() } } })
```

### `mep.repl` — a per-filetype REPL, in a real terminal split

One REPL kept alive per filetype (`config.options.scope = 'buffer'` for
one per source buffer instead) in a real `:terminal` split — `mep.run`'s
own no-shell `vim.fn.jobstart(cmd, { term = true })` idiom, and `mep.
project`'s own terminal-split usage as precedent for the split itself.
`send_line`/`send_selection`/`send_buffer` write to it via `vim.fn.
chansend`. Starting a REPL as a side effect of a send call (the first
one for a given filetype/buffer) briefly focuses the new split, then
returns focus to wherever it was — sending a line shouldn't strand you
in the REPL window. `mep.repl.registry` is a curated filetype -> launch-
command table (BYO interpreter on PATH, `mep.org.babel`'s own language
table as precedent for the pattern, though not the same table — a REPL
launch command is a different program/flags than "run this script file",
e.g. Python's REPL is a bare `python3`, not `python3 <file>`) covering
languages with a real, standard, interactive REPL (Python/Lua/JS/Ruby/R/
Julia/Clojure/Haskell/OCaml/PHP/Elixir/Scala/bash) — several `mep.org.
babel` supports for script execution (C/C++/Rust/Go/Java/...) have no
comparably standard interactive mode and are deliberately left out.

```lua
require('mep.repl').setup({}) -- scope='filetype', keymaps.send_line=<leader>sl, send_selection=<leader>ss (visual), send_buffer=<leader>sb, jump_to_repl=<leader>sr, jump_back=<leader>sc
require('mep.repl').setup({ scope = 'buffer' })
require('mep.repl').setup({ commands = { python = { 'ipython' } } })
```

`jump_back` (default `<leader>sc`) is bound buffer-local, inside each
REPL terminal buffer this library creates itself — not globally, since
there's no single "current code buffer" to jump back to from just
anywhere.

| Command                      | Lua API                                   | What it does                     |
|----------------------------------|------------------------------------------------|---------------------------------------|
| `:MepReplSendLine`           | `require('mep.repl').send_line()`             | Send the current line            |
| `:MepReplSendSelection`      | `require('mep.repl').send_selection(...)`      | Send a line range (visual range-capable) |
| `:MepReplSendBuffer`         | `require('mep.repl').send_buffer()`            | Send the whole buffer            |
| `:MepReplJump`               | `require('mep.repl').jump_to_repl()`           | Jump to (starting if needed) the REPL window |

### `mep.snippet` — a tabstop/placeholder snippet engine

A full tabstop/placeholder expansion engine in plain Lua — no textmate/
VSCode JSON format. `$1`/`${1}` bare tabstops, `${1:default}` with a
pre-filled placeholder, `$0` as the final cursor position (synthesized at
the end of the snippet if the body doesn't include one). Stops are
tracked with **extmarks, not frozen positions** — the same idiom `mep.ai`
uses for its own streaming-insert landing spot, adapted from a single
tracked point to a tracked range (independent start/end gravity, so
typing inside a stop grows it in place).

Snippets are registered per filetype, in plain Lua:

```lua
require('mep.snippet').add('lua', {
  { trigger = 'fn', body = 'function $1($2)\n\t$0\nend' },
})
```

`<Tab>` (configurable, `tab_keymap = false` to opt out of both keymaps
entirely) expands the trigger word immediately before the cursor — even
outside `mep.completion`'s own popup — or jumps to the next tabstop if a
snippet is already being navigated; `<S-Tab>` jumps backward. Neither
falls back to a *selected* placeholder (no Neovim Select-mode
integration) — jumping to a stop with a default just places the cursor
at its start; same for a same-index tabstop reused more than once in one
body (`$1` twice) — each occurrence navigates independently rather than
mirroring live edits between them.

```lua
require('mep.snippet').setup({}) -- tab_keymap = true
require('mep.snippet').setup({ tab_keymap = false }) -- don't bind <Tab>/<S-Tab> at all
```

A fourth `mep.completion` source (`sources = {'lsp','buffer','path',
'snippet'}`, now the default) surfaces registered triggers in the same
popup — see that library's own section below, including how accepting a
snippet-shaped item (from this source, or an LSP completion whose
`insertTextFormat` is `Snippet`) now expands through this engine instead
of inserting `$1`/`$0` placeholders as literal text.

### `mep.todoscan` — a project-wide TODO/FIXME/HACK/NOTE comment scanner

Explicitly distinct from `mep.activitybar`'s own manual, persisted todo
list — no shared data store between the two; this library only ever
*reads* comments already in the code, never writes anything.

`:MepTodoScan` (`require('mep.todoscan').picker()`) opens a `mep.picker`-
backed list of every configured keyword found across the project — `rg`
when available (respects `.gitignore`, skips `.git`, the same
optional-external-tool posture `mep.picker.find_files`/`live_grep` take
toward it), falling back to a synchronous walk+grep otherwise. `<CR>`
jumps to the comment.

Every open, file-backed buffer also gets **live in-buffer marking** —
a sign-column glyph plus a highlight group on the matched word itself
(`MepTodoScanTodo`/`Fixme`/`Hack`/`Note` for the default four keywords,
derived the same way for any custom keyword) — recomputed on a debounce
after text changes/saves, the same "debounced attach/detach lifecycle"
`mep.git.gutter` uses (`config.options.highlight = false` to opt out).

```lua
require('mep.todoscan').setup({}) -- keywords={'TODO','FIXME','HACK','NOTE'}, debounce_ms=300, highlight=true
require('mep.todoscan').setup({ keywords = { 'TODO', 'XXX' } })
require('mep.todoscan').setup({ highlight = false }) -- picker only, no live in-buffer marking
require('mep.todoscan').setup({ signs = { TODO = '!!' } }) -- override a keyword's sign-column glyph
```

| Command         | Lua API                             | What it does                                  |
|------------------|-----------------------------------------|----------------------------------------------------|
| `:MepTodoScan`  | `require('mep.todoscan').picker()`  | Search TODO/FIXME/HACK/NOTE comments across the project |

### `mep.zen` — zen mode: hide the chrome, center the buffer

`:MepZenToggle` (`require('mep.zen').toggle()`) hides `mep.activitybar`,
closes `mep.filetree`/`mep.symbols` if open, turns off the gutter
(`number`/`relativenumber`/`signcolumn` on the current window — the same
window-local save/restore idiom `mep.dashboard.ui` uses for its own
gutter suppression) and `mep.chrome`'s statusline/winbar/statuscolumn,
then centers the current window's buffer toward `config.width` columns
(default 90) by adding two blank, `winfixwidth` padding splits — real
windows, not a virtual margin. Exiting restores the exact prior state:
only a target that was actually open/enabled before entering zen mode
gets reopened/re-enabled again, and the padding splits just close.

Every piece is individually toggleable (`config.hide`, same
"everything independently disableable" convention `mep.sanity` uses),
and each of `mep.activitybar`/`mep.filetree`/`mep.symbols`/`mep.chrome`
is a soft, optional dependency — using zen mode without one of them
loaded just skips that piece.

```lua
require('mep.zen').setup({}) -- width=90, hide={activitybar=true, filetree=true, symbols=true, gutter=true, chrome=true}
require('mep.zen').setup({ width = 120 })
require('mep.zen').setup({ hide = { chrome = false } }) -- leave the statusline/winbar/statuscolumn alone
```

| Command         | Lua API                        | What it does        |
|------------------|-------------------------------------|--------------------------|
| `:MepZenToggle` | `require('mep.zen').toggle()`  | Toggle zen mode      |

### `mep.picker` — search and pick, with a preview sidebar

A `Picker` (`lua/mep/picker/engine.lua`) drives a floating-window layout —
prompt on top, results below it, preview sidebar on the right — with fuzzy
matching (`mep.picker.matcher`, a dependency-free fzf-style subsequence
scorer) and live preview of the selected item.

Five ready-made pickers, each its own source module under
`lua/mep/picker/sources/`:

| Command            | Lua API                          | What it searches                              |
|---------------------|-----------------------------------|------------------------------------------------|
| `:MepFindFiles`     | `require('mep.picker').find_files()`   | Project files (`rg --files`, or a pure-Lua walk if `rg` isn't installed) |
| `:MepLiveGrep`      | `require('mep.picker').live_grep()`    | File contents across the project, via `rg` (required) |
| `:MepProjectSearch` | `require('mep.picker').live_grep()`    | Alias of `:MepLiveGrep`, for a `<leader>p*`-mnemonic keymap |
| `:MepBufferSearch`  | `require('mep.picker').buffer_search()`| Lines of the current buffer                     |
| `:MepBuffers`       | `require('mep.picker').buffers()`      | Open (listed, loaded) buffers, most recently used first |
| `:MepCommands`      | `require('mep.picker').commands()`     | User-defined Ex commands (buffer-local + global, `:Mep*` included) |

`find_files`/`live_grep`/`buffers` accept an optional `opts` table (`{ cwd
= ... }` for the first two, none for `buffers`); `buffer_search` takes
`{ bufnr = ..., winid = ... }`; `commands` takes `{ bufnr = ... }`
(default the current buffer), scoping which buffer-local commands are
included alongside every global one. `<CR>` on a command runs it
directly, or prompts (`vim.ui.input`) for its argument text first if its
`nargs` calls for any.

#### Keymaps inside the picker (prompt window, insert or normal mode)

| Key                          | Action           |
|-------------------------------|------------------|
| `<C-n>` / `<Down>` / `<C-j>`  | Next result       |
| `<C-p>` / `<Up>` / `<C-k>`    | Previous result   |
| `<CR>`                        | Select            |
| `<Esc>` / `<C-c>`             | Close             |

Type to filter — filtering is live, debounced (~20ms for local lists, ~120ms
for the `rg`-backed live grep so it doesn't spawn a process per keystroke).
Both the debounce timings and the keymaps above are configurable via
`require('mep.picker').setup({...})` — see `lua/mep/picker/config.lua` for
the full defaults table (`debounce_ms.static`/`debounce_ms.dynamic`,
`keymaps.select`/`close`/`next`/`prev`, each a list of lhs strings mapped
in both insert and normal mode). Picker functions work with sensible
defaults even if `setup()` is never called.

#### Trigger keymaps (outside the picker, e.g. replacing `/`)

`triggers.buffer_search` (unbound by default) is a list of normal-mode lhs
strings that open `buffer_search()` from wherever you already are —
useful for replacing Neovim's native `/` command-line search with a fuzzy
picker over the buffer's lines:

```lua
require('mep.picker').setup({ triggers = { buffer_search = { '/' } } })
```

Applied by `lua/mep/picker/keymaps.lua`, wired up from `setup()` the same
way `mep.sanity`'s keymaps are.

#### Highlight groups

- `MepMatch` — fuzzy-matched characters in the results list (links to `Search`)
- `MepPreviewLine` — the target line in the preview pane (links to `CursorLine`)

### `mep.project` — a small, persisted list of project directories, with a picker

A `mep.picker`-backed picker over a JSON-persisted list of directories —
like `mep.theme.picker`/`mep.url.pick`, a library-specific picker (its own
persisted state, not a stateless `mep.picker.sources.*` file).

```lua
require('mep.project').picker() -- or :MepProjects
```

- `<C-a>` (`config.options.keymaps.add`) inside the picker adds the
  current working directory to the list and refreshes the results —
  there's no separate "add project" command, this is the only way in.
- `<C-d>` (`config.options.keymaps.delete`) inside the picker deletes
  the currently selected project from the list and refreshes — only the
  list entry; nothing on disk is touched.
- Picking one `cd`s into it, then opens its README —
  `config.options.readme_names` (default `{'README.org', 'README.md'}`,
  checked in that order) — if it has one; just the `cd` otherwise. The
  preview pane shows the same README while you browse.
- Also sets up the rest of the project layout, unless turned off:
  `mep.filetree` rooted there (`config.options.open_filetree`, on by
  default — closes and reopens the tree if it was already showing a
  *different* project, so it's never stale), and a `:terminal` below the
  README (`config.options.open_terminal`, on by default; sized to
  `config.options.terminal_height_ratio` — `0.3` by default, i.e. the
  terminal gets ~30% of the height, the README the rest). Focus ends
  back on the README either way.
- Persisted to `config.options.persist_path` (default `stdpath('data')
  .. '/mep_projects.json'`), a plain JSON array of paths. Duplicate
  `add`s (the same directory referenced two different ways) are ignored.

```lua
require('mep.project').setup({ readme_names = { 'readme.txt' } })
require('mep.project').setup({ open_terminal = false }) -- skip the terminal, keep the file tree
require('mep.project').setup({ terminal_height_ratio = 0.2 }) -- a smaller terminal
require('mep.project').add('/path/to/project') -- add one without opening the picker
```

### `mep.treesitter` — activates treesitter, installs common parsers

Two separate things, both on by default:

- **Activation** (`mep.treesitter.activate`) — starts highlighting
  (`vim.treesitter.start`), and optionally folding
  (`vim.treesitter.foldexpr()`), for any buffer whose filetype has a
  parser available *from anywhere* — bundled with Neovim (c, lua,
  markdown, vim, vimdoc, query out of the box), installed by mep, or
  installed by anything else. Pure `vim.treesitter` API, no network, no
  compiler — this part always works, on any OS.
- **Installing** (`mep.treesitter.install`) — a curated registry of
  ~40 common languages, including `org` for `mep.org`
  (`mep.treesitter.parsers`, verified against nvim-treesitter's own
  registry rather than hardcoded from memory, since several of these have
  moved GitHub orgs over time). Missing parsers are
  fetched and compiled in the background on `setup()`: `git clone
  --depth 1` the grammar, then a system C compiler
  (`cc`/`gcc`/`clang` — MSYS2/mingw-gcc on Windows works, a pure
  MSVC-only setup does not) builds `parser/src/*.c` into a shared
  library, installed to `stdpath('data')/site/parser/` (already on
  `runtimepath` by default, so nothing else needs configuring). If git or
  a compiler isn't found, this degrades gracefully — one warning, nothing
  installed, activation still works for whatever's already available.
  This is genuinely a heavier default than any other mep library's
  `setup()` — see `treesitter = { ensure_installed = false }` below to
  opt out and keep only activation. Each install also copies that
  grammar's own upstream `queries/` directory (highlights.scm and
  whatever else it ships) to `stdpath('data')/site/queries/<lang>/`,
  independently of the grammar itself — a *compiled* parser alone gives
  `vim.treesitter` a parse tree, not colors; the query file is what
  highlighting actually reads. Neovim bundles its own for a handful of
  languages (c, lua, markdown, vim, vimdoc, query) and this project ships
  its own hand-written one for `org` (`queries/org/highlights.scm` — see
  its own header comment for why), but every other curated language gets
  its query copied from its own grammar repo, the same reference query
  every tree-sitter CLI/playground consumer uses. A language whose repo
  ships no `queries/` directory at all just doesn't highlight, same
  graceful-miss as everywhere else.

```lua
require('mep.treesitter').setup({}) -- highlight=true, fold=false, ensure_installed=true (the curated list)
require('mep.treesitter').setup({ ensure_installed = { 'lua', 'python', 'rust' } }) -- just these
require('mep.treesitter').setup({ ensure_installed = false }) -- activate-only, install nothing
require('mep.treesitter').setup({ fold = true })
```

| Command                      | What it does                                    |
|--------------------------------|---------------------------------------------------|
| `:MepTreesitterInstall <name>` | Install one parser (Tab-completes the curated list) |
| `:MepTreesitterInstallAll`     | Install every parser in the curated registry        |

### `mep.org` — org-mode structure and highlighting

**Scope note**: work toward full org-mode parity is in progress — see
[`ORGMODE_ROADMAP.md`](./ORGMODE_ROADMAP.md) for what's shipped vs. not
yet. Real org-mode (and even the mature community
[nvim-orgmode](https://github.com/nvim-orgmode/orgmode) project) is a huge
surface, so it's being built in phases rather than attempted all at once;
what's below is what's landed so far — headline structure and editing,
TODO state, priorities, dates/scheduling, tags (inheritance, match
syntax, fast selection, alignment), links (parse, conceal, follow,
insert, store), plain lists (continuation, indent/outdent, renumber),
sparse-tree search, property drawers, clocking and effort estimates,
capture templates, an agenda (day/week views, global TODO list, tag
search, all aggregated across `agenda_files`), org-babel (execute/tangle
`#+begin_src` blocks), org-export (ascii/markdown/html backends),
footnotes, generic special blocks (quote/verse/example/center), macros,
`#+INCLUDE:` file inclusion, org-id, org-attach-style attachments,
checkboxes and statistics cookies, folding/visibility, sorting,
narrowing, archiving, refiling, and easy templates, with syntax
highlighting layered on top via `mep.treesitter`.

Everything except highlighting is pure line-pattern parsing
(`mep.org.headline`) — no tree-sitter parser required, so all of the
structure editing below works immediately, even before (or without) the
`org` parser being installed:

- **`mep.org.outline`** — `next_headline`/`prev_headline`/
  `parent_headline`/`subtree_end`; `change_level` (promote/demote one
  headline, matching Emacs org-mode's plain `M-Left`/`M-Right`) and
  `change_level_subtree` (the whole subtree, preserving relative depth);
  `move_subtree` (swap with the previous/next sibling subtree).
- **`mep.org.edit`** — `insert_headline`/`insert_todo_headline`: add a
  new sibling after the current subtree, positioning the cursor ready to
  type the title.
- **`mep.org.todo`** — `cycle(bufnr, lnum, todo_keywords)` steps a
  headline through your configured TODO states, then to no keyword, then
  back to the first.
- **`mep.org.priority`** — `set`/`cycle` a `[#A]`-style priority cookie
  (single alphanumeric character, right after the TODO keyword if any).
  `cycle` steps through a configured list (default `A`/`B`/`C`), then to
  no priority, then back to the first — real org-mode's `org-priority`
  is prompt-based; this cycles instead, consistent with `mep.org.todo`.
- **`mep.org.timestamp`** — active `<2024-01-01 Mon>` / inactive
  `[2024-01-01 Mon]` timestamps, with an optional time (or time range)
  and repeater (`+1w`, `++1w`, `.+1w`). `insert_or_edit` (interactive,
  via `vim.ui.input`) inserts a new one at the cursor or edits the one
  the cursor is already on; `adjust_under_cursor(bufnr, win, delta)`
  shifts the date under the cursor by `delta` days, recomputing the
  weekday and rolling over month/year boundaries.
- **`mep.org.plan`** — `SCHEDULED:`/`DEADLINE:` planning lines (the line
  immediately after a headline). `set_scheduled`/`set_deadline` create or
  update the line; `schedule_interactive`/`deadline_interactive` prompt
  via `vim.ui.input` (real org-mode's `org-schedule`/`org-deadline`).
- **`mep.org.tags`** — extends Phase 0's basic `:tag1:tag2:` parsing:
  `effective_tags` (own tags plus every ancestor's, deduped — real
  org-mode tag inheritance), `set_tags`/`toggle_tag`, `align_line`/
  `align_buffer` (pad trailing tags to a consistent column, single space
  on overflow rather than truncating), and `select_interactive` — a
  small floating popup with an auto-assigned single-letter shortcut per
  configured tag (`config.tags`) to toggle it on/off, `<CR>` to confirm,
  `<Esc>`/`q` to cancel (real org-mode's fast-tag-selection; kept off
  `<C-c><C-c>`, which this project already dedicates to checkboxes).
- **`mep.org.tagmatch`** — `+tag-tag`/`|` filter-expression parsing and
  evaluation against a tag list (AND by concatenation, `|` for OR, AND
  binds tighter than OR) — pure predicate logic with no buffer access,
  meant to be shared by sparse-tree search (Phase 6) and agenda
  (Phase 7) once those exist; no parenthesized grouping, a deliberate
  scope simplification over real org-mode's fuller match syntax.
- **`mep.org.link`** — `[[target]]`/`[[target][description]]`, pure
  line-pattern parsing (the real grammar has no dedicated link node at
  all — confirmed against `node-types.json`). `follow` dispatches the
  target under the cursor: a URL/`mailto:` opens via `vim.ui.open`
  (Neovim 0.10+); `id:`/`#custom-id` jump to a headline with that
  property; `file:path[::N|::*Heading]` opens a file, optionally
  jumping to a line or headline in it; `*Heading` (or a bare target,
  tried as a heading search first) jumps within the buffer. `id:`/
  `#custom-id` lookup reads a headline's own `:PROPERTIES:` drawer with
  the smallest scanner that gets this working now — full property-drawer
  parsing is Phase 7's job, the same "narrow slice now" tradeoff
  `mep.org.archive` already made. `insert_interactive` prompts for
  target + description (or, in visual mode, wraps the selection as the
  description and prompts only for target); `store_link` remembers a
  link to a headline (preferring `CUSTOM_ID`, then `ID`, then a
  `*Title` fallback) as the next `insert_interactive`'s default target —
  only the single most recent one, not a history list.
- **`mep.org.linkconceal`** — visually hides the raw `[[...][` / `]]`
  syntax via extmarks (not tree-sitter — again, no link node to hang a
  `@conceal` capture off of), showing only the description or bare
  target. Recomputed on `TextChanged`/`TextChangedI`/`InsertLeave`;
  purely programmatic buffer edits (not real typing) need an explicit
  `apply(bufnr)` call to refresh.
- **`mep.org.checkbox`** — `toggle`/`is_checked` for `- [ ]`/`- [X]` list
  items.
- **`mep.org.statistics`** — keeps a headline's `[2/5]`/`[40%]` cookie in
  sync with either the checkboxes or direct child headlines' TODO state
  underneath it, and propagates the update up through every ancestor with
  its own cookie.
- **`mep.org.sort`** — sort sibling subtrees (alphabetically, by TODO
  state, or by priority) under the same parent, moving each whole subtree
  as a block.
- **`mep.org.narrow`** — a practical, fold-based approximation of
  Emacs-style buffer narrowing to a single subtree (not true narrowing:
  see the module for the caveat).
- **`mep.org.archive`** — move a subtree out to a
  `<file>_archive.org` alongside the original, recording where/when it
  came from.
- **`mep.org.refile`** — move a subtree to become the last child of
  another headline (in the current buffer), promoting/demoting it to
  fit; `refile_interactive` picks the target via `mep.picker`.
- **`mep.org.visibility`** — global visibility cycling: overview
  (top-level headlines only) → contents (every headline, no body text) →
  all (everything shown) → back to overview.
- **`mep.org.templates`** — "easy templates": typing `<s` then Tab
  expands to a `#+begin_src`/`#+end_src` block (and similarly for
  `example`/`quote`/`center`/`verse`/`comment`).
- **`mep.org.list`** — plain bulleted (`-`/`+`/indented `*`) and ordered
  (`1.`/`1)`) list items. `continue_at_cursor` (insert-mode `<CR>`) picks
  up the same bullet or next number on a new line (a fresh, unchecked
  `[ ]` for a checkbox item), auto-renumbering the run; an *empty* item
  exits the list instead of adding another one. `indent_item`/
  `outdent_item` shift an item and its more-indented continuation lines
  as a unit; `renumber` fixes up a run's numbers from 1 (always
  restarting from 1, and requiring a contiguous run with no blank-line
  gaps — simpler than real org-mode on both counts).
- **`mep.org.sparse`** — sparse-tree search: `show_matching(bufnr, win,
  predicate)` folds away everything except headlines a predicate
  accepts, their own immediate body text, and their ancestor headlines
  (the "path" to each match) — real org-mode's `C-c /`.
  `tag_search_interactive` builds the predicate from `mep.org.tagmatch` +
  `mep.org.tags.effective_tags` (inheritance-aware); `todo_search_interactive`
  picks a TODO state via `mep.picker`. `clear` restores the previous
  fold configuration; the `widen` keymap tries both this and
  `mep.org.narrow.widen`, since a window is never narrowed *and*
  sparse-tree-restricted at once in practice.
- **`mep.org.property`** — `:PROPERTIES: ... :END:` drawers: `get`/`set`/
  `remove` a property on a headline's own drawer (creating/deleting it as
  needed), `find_by` to search for a headline by property value,
  `set_interactive` (`<C-c><C-x>p`, prompts key then value). This
  generalizes the narrow ad-hoc `:ID:`/`:CUSTOM_ID:` scanner
  `mep.org.link` carried since Phase 5 — that module now delegates here.
- **`mep.org.clock`** — clocking: `clock_in`/`clock_out`
  (`<C-c><C-x><C-i>`/`<C-c><C-x><C-o>`) add/close a `CLOCK:` entry in a
  headline's `:LOGBOOK:` drawer; only one clock can be open at a time,
  found by scanning the buffer for an open entry rather than tracked as
  session-only state, so it survives buffer reloads and Neovim restarts.
  `status(bufnr)` returns a `"Title (H:MM)"` string for your own
  statusline (e.g. `%{v:lua.require'mep.org.clock'.status(0)}` — this
  project has no opinion on statusline plugins, so it's a plain function,
  not an integration). `effort(bufnr, lnum)` reads the `Effort:`
  property as minutes (prep for Phase 9's agenda summing).
  `insert_report`/`clock_report` (`<C-c><C-x><C-r>`) inserts or refreshes
  a `#+BEGIN: clocktable ... #+END:` block with recursive per-headline
  totals.
- **`mep.org.capture`** — capture templates: `config.capture_templates` is
  a list of `{ key, description, target = { file = ..., headline = ...
  }, template = "..." }`; `<C-c>c` (normal or visual — a visual selection
  becomes `%i`) opens `mep.picker` over the configured templates, expands
  the chosen one's placeholders (`%?` cursor position, `%a` an org-link
  annotation back to where capture was triggered, `%i` initial content,
  `%T`/`%U` active timestamp, `%t`/`%u` inactive timestamp — real
  org-mode distinguishes "with time" `%U`/`%u` from date-only `%T`/`%t`,
  this project doesn't, a deliberate simplification — `%^{PROMPT}` for a
  `vim.ui.input` prompt, `%%` literal percent) into a floating popup
  (filetype `org`, so the rest of this library's keymaps work inside it
  too) for review/editing; `<C-c><C-c>` files it into the target and
  saves, `<C-c><C-k>` aborts. Real org-capture is bound *globally* (any
  buffer) since quick capture from wherever you are is the whole point;
  this project only activates keymaps inside org buffers, so bind
  `require('mep.org').capture.capture_interactive(templates)` to a
  global keymap yourself for that.
- **`mep.org.agenda`** — aggregates scheduled items, deadlines, TODO
  state, and tags across every `config.agenda_files` file (literal paths
  and/or glob patterns, e.g. `{'~/notes/*.org'}`) into one scratch
  buffer. `<C-c>a` prompts (`vim.ui.select`) for a view: day, week
  (7 days from today), the global TODO list (every outstanding
  TODO-stated headline), or a tag search (`mep.org.tagmatch` syntax,
  prompted via `vim.ui.input`). Reads live/unsaved buffer content for any
  agenda file already open, not just what's on disk. Deadlines start
  appearing `config.deadline_warning_days` (default `14`, matching real
  org-mode) days ahead of due, and an overdue non-repeating deadline
  keeps showing on today's view until resolved; a *repeating* deadline
  (`+1w` etc.) is never treated as overdue, since it recurs regardless.
  All three repeater cadence variants (`+`/`++`/`.+`) are treated
  identically for occurrence-matching — a deliberate simplification,
  since `.+`'s real semantics ("N units after whenever this was last
  completed") need completion-history tracking this project doesn't have.
  From the agenda buffer: `<CR>` jumps to the entry's source and closes
  the agenda, `t` cycles its TODO state in place (buffer only, not saved
  to disk) and redraws, `s` reschedules it
  (`mep.org.plan.schedule_interactive`), `q` closes the agenda and
  restores focus to wherever it was opened from. Tag/property search only
  covers tags in this phase — `mep.org.property` (Phase 7) is there for a
  future property-search view. Like capture, real org-agenda is a
  *global* keymap; this project only activates keymaps inside org
  buffers, so bind `require('mep.org').agenda.dispatch_interactive(config)`
  to a global keymap yourself for that.
- **`mep.org.babel`** — execute `#+begin_src <lang> [header args] ...
  #+end_src` blocks and tangle their bodies to real files. `<C-c>e`
  executes the block at the cursor, writing its output into a
  `#+RESULTS:` block below it (a single `: line` for one-line output,
  a `#+begin_example ... #+end_example` block for more, replacing an
  existing results block in place); `<C-c>E` tangles every block in the
  buffer that has a `:tangle target` header arg out to real files
  (blocks sharing a target are concatenated in document order). Not
  bound to real org-babel's own `C-c C-v C-e`/`C-c C-v C-t` (an Emacs
  `C-c C-v` prefix-map convention) — confirmed empirically that `<C-v>`
  can't work as the first key of a Neovim mapping at all (it hard-codes
  to entering Visual-Block mode before mapping resolution ever sees it);
  `<C-c>e`/`<C-c>E` instead mirrors this project's own `narrow`/`widen`
  (`<C-c>n`/`<C-c>N`) convention: lowercase acts on the block at point,
  uppercase acts on the whole buffer. Supports `lua`/`python`/`sh`
  (`bash`/`sh` alias)/`javascript` (`js` alias)/`typescript` (`ts` alias,
  via `bun`)/`ruby`/`perl`/`R`/`php`/`elixir`/`julia`/`clojure` (via `bb`,
  falling back to `clojure`)/`csharp` (`cs`/`c#` aliases, via `dotnet
  run` — .NET's own "file-based apps" mode, no `.csproj` needed)/`nim`
  (via `nim r`)/`crystal` (via `crystal run`)/`kotlin` (via `kotlin
  <file>.kts` script mode)/`haskell` (via `runghc`)/`ocaml` (via the
  `ocaml` toplevel, run as a script), plus the compiled languages
  `c`/`c++` (`cpp` alias)/`rust`/`go`/`fortran`/`scala`/`zig` (via `zig
  run` — no separate binary-management step, same as `nim`/`crystal`
  above, but still needs `:main`'s entry-point wrapping, since Zig only
  allows declarations at its own top level)/`java` (a real two-step
  `javac`+`java`, the one language here where the "binary" `execute`
  runs afterward is actually a directory of `.class` files, not a
  single executable — see `mep.org.babel`'s own header comment)/`d`
  (`dmd`, its own `-of=<path>` output flag needing a custom
  `compile_cmd` the way Go's own `build -o` subcommand-before-flags
  shape already does), each resolved to whatever interpreter or
  compiler is actually on PATH
  (`python3` falling back to `python`, `sh` falling back from `bash`) —
  an unavailable language warns via `vim.notify` rather than erroring,
  the same graceful degradation `mep.treesitter` uses for a missing C
  compiler. Which languages get added here at all: a real LSP server
  *and* a real tree-sitter grammar have to exist for it first (`mep.lsp.
  servers`/`mep.treesitter.parsers` below) — this repo's own `flake.nix`
  devShell provisions a toolchain/server for every one of them, purely
  so trying a language out doesn't need anything installed globally.
  Header args: `:var name=value` (repeatable) injects a
  prelude assignment before the body in the target language's own
  syntax (a bare number passes through as a literal, anything else
  becomes a quoted string — scalars only, no org-table/list injection);
  `:results value` (vs. the default `output`) treats the block's last
  non-blank line as an expression and auto-prints it instead of running
  it as a plain statement — a deliberate, documented simplification of
  real org-babel's per-language value-capture machinery, and not
  meaningful for shell (a shell script's output already *is* its value,
  so `:results value` behaves like `output` there). For a compiled
  language, `:includes` (e.g. `:includes <stdio.h>`, whitespace-
  separated for more than one) prepends each token as that language's
  own import form, and `:main yes` wraps the body in a minimal
  entry-point (`int main() { ... }`/`fn main() { ... }`/`package main;
  func main() { ... }`) for a block that's bare statements rather than a
  complete program — the *default* (no `:main`, or an explicit `:main
  no`) assumes the block is already a self-contained program, since
  that's the common case for something worth pasting into a src block
  (see `mep.org.polyglot`'s own section above for the identical `:main`
  contract its shadow buffers use). A failed run still writes whatever
  stdout it produced and separately warns with the first substantive
  line of stderr — skipping a leading `# <package>` header `go build`
  prints before the real error when compiling a file outside a module —
  so failures are visible without an empty results block silently
  swallowing them. Explicitly deferred, likely indefinitely: persistent
  per-block sessions, and the rest of real org-babel's header-argument
  surface (`:session`, `:noweb`, `:cache`, etc.) beyond `:results`/
  `:var`/`:tangle`/`:includes`/`:main`.
- **`mep.org.fold`** — a headline-depth `foldexpr`, used by the per-fold
  `<Tab>` toggle. Deliberately not the same as generic `mep.treesitter`
  folding: org's fold unit is the headline subtree (heading + body +
  child headlines, as one block), not every syntax node.
- **`mep.org.block`** — generic `#+BEGIN_<kind> ... #+END_<kind>` parsing
  (quote/verse/example/center, or any other block name), the same
  line-pattern style as `mep.org.babel.find_blocks` generalized off a
  hard-coded `"src"`. Feeds `mep.org.export`'s semantic per-kind
  rendering; highlighting already treats any such block as one opaque
  span generically.
- **`mep.org.footnote`** — `[fn:name]` references, `[fn:name:inline
  def]`/`[fn::anonymous inline def]` inline definitions, and standalone
  `[fn:name] text` definition lines (single-line, like
  `mep.org.clock`'s `:LOGBOOK:` notes). `<C-c><C-x>f` (real
  org-footnote-action's own binding) is context-sensitive:
  `goto_counterpart` navigates from a reference to its definition (or
  back) when the cursor is on either half, otherwise `insert_interactive`
  prompts for a name (blank auto-numbers) and definition text, inserting
  the reference at the cursor and appending the definition after the
  last existing one.
- **`mep.org.macro`** — `#+MACRO: name value with $1 $2 ...`
  definitions, expanded at `{{{name}}}`/`{{{name(arg1,arg2)}}}` (`\,`
  escapes a literal comma in a call's arguments). `mep.org.export` runs
  this over paragraph/list-item/headline text and quote/verse/center
  block bodies (not `src`/`example`, matching real org-mode not
  expanding macros inside literal content) before interpreting markup.
  An unknown macro name is left untouched rather than expanding to
  empty; a missing argument position expands to empty.
- **`mep.org.include`** — `#+INCLUDE: "path" [:lines "M-N"] [src lang]`
  file inclusion, resolved recursively (depth-guarded and
  cycle-detected) before `mep.org.export` builds its document model. A
  relative path resolves against the including file's own directory; an
  unreadable file or a detected cycle is left as the literal directive
  line with a `vim.notify` warning.
- **`mep.org.id`** — org-id: `generate` (a random v4-UUID-shaped
  string); `get_or_create` reads or creates a headline's `:ID:` property
  (`<C-c><C-x>i`); `find` looks up a headline by `:ID:` value
  (buffer-local only, no cross-file index — the same scope
  `mep.org.refile` documents for cross-file work).
- **`mep.org.attach`** — org-attach-style per-headline attachment
  directories: `<file-dir>/<config.attach_dir>/<id[1:2]>/<id[3:]>/`
  (real org-attach's own ID-based default method, including its 2/rest
  split), auto-creating an `:ID:` via `mep.org.id` if needed.
  `attach`/`attach_interactive` (`<C-c><C-a>`, prompts a source path)
  copy a file in by basename; `list` reads back what's attached.
- **`mep.org.export`** — the org-export framework: `parse`/`parse_lines`
  build a *flat*, ordered document model (`headline`/`paragraph`/
  `list_item`/`src`/`block` elements, each carrying its own
  `level`/`depth`) from a buffer, after resolving `#+INCLUDE:` and
  collecting `#+MACRO:` definitions — the same flat-list-not-a-tree
  representation `mep.org.agenda`'s `collect_entries` already uses for
  headlines; each backend reconstructs nesting itself while rendering.
  `tokenize_inline` (shared by every backend) turns text into an ordered
  token stream (bold/italic/underline/strike/code/verbatim/link/
  footnote). `#+TITLE:`/`#+AUTHOR:`/`#+DATE:` and `#+OPTIONS: toc:nil
  num:nil` (table of contents and `"1.2.3"`-style headline numbering,
  both on by default) are respected; a `:noexport:`-tagged headline (and
  its whole subtree) is dropped, matching real org-mode's own default
  `org-export-exclude-tags`. `<C-c><C-e>` (real org-export-dispatch's
  own binding) prompts for a backend (`vim.ui.select`) and writes to
  `default_path` (same directory/basename as the source file, with the
  backend's extension — `.txt`/`.md`/`.html`); `export_subtree` exports
  just the subtree at point, honoring a `:EXPORT_TITLE:` property
  override and renormalizing descendant levels so the first child
  becomes level 1 (matching real org-mode's own subtree-export
  behavior). Every `src` block is executed during export (via
  `mep.org.babel.run_async`, the same compile-then-run/interpreter
  dispatch `mep.org.babel.execute` uses interactively, just with no live
  buffer to write into) and its output embedded right after the code,
  unless `:exports code`/`none` narrows what's shown, `:eval never`/
  `no-export` opts the block itself out, or `opts.eval = false` disables
  it for the whole export; `:exports results` shows only the output, and
  `:exports none` drops the block entirely. Execution is fully
  asynchronous — `export_to_file`/`export_subtree`/`dispatch_interactive`
  all take an `on_done` callback rather than returning the written path
  directly, and every pending block across the document runs
  concurrently, so a slow or compiled block never locks up the editor
  (`parse`/`parse_lines` stay synchronous and never run babel themselves;
  `parse_async`/`parse_lines_async` are the async pair that actually run
  the pending jobs before handing back a fully-populated document). This
  is a deliberate deviation from real org-babel's own default `:exports`
  value (`"code"` — nothing run/shown unless a block
  opts in with `:exports both`/`results`); a `:cache yes` block reuses
  `mep.org.babel.results_cache` under the same key `M.execute`'s own
  `<C-c>e` would use, so exporting right after a manual run hits the
  cache instead of re-running. Three backends:
  - **`mep.org.export.ascii`** — plain text; emphasis markers are left
    as literal characters (`*bold*` stays `*bold*`, matching real
    org-mode's own ascii backend), since plain text has no other way to
    signal emphasis. Level 1/2 headlines are underlined (`=`/`-`).
  - **`mep.org.export.markdown`** — `**bold**`, `_italic_`,
    `<u>underline</u>` (Markdown's own inline-HTML escape hatch —
    standard Markdown has no native underline), `~~strike~~`, fenced
    ` ```lang ` code blocks, footnotes as `[^name]`/`[^name]: text`
    (Markdown's standard footnote extension).
  - **`mep.org.export.html`** — `<h1>`-`<h6>` (clamped), properly nested
    `<ul>`/`<ol>` reconstructed from the flat list-item stream, all text
    HTML-escaped, a disabled `<input type="checkbox">` for checkbox
    items, footnotes as `<sup>`/a bottom footnotes `<div>`.

  Real org tables aren't part of the model at all — a `|`-delimited line
  just falls through to plain paragraph text. LaTeX/PDF and ODT backends
  are likely deferred/out of scope; see `ORGMODE_ROADMAP.md`.
- **Highlighting** — delegates to `mep.treesitter`, which owns the `org`
  parser entry (same install pipeline, same graceful degradation without
  git/a compiler). The query file (`queries/org/highlights.scm`) is
  hand-written against the real grammar's node types rather than adapted
  from nvim-orgmode's own query, which leans on custom Lua predicates
  (`#org-is-headline-level?` etc.) that only exist if that plugin
  registers them; this one uses only predicates built into Neovim's query
  engine, so it works standalone — the tradeoff is only the two default
  (`TODO`/`DONE`) keywords are recognized by the *static* query (the
  structural TODO cycling above still respects a custom `todo_keywords`
  list either way). Per-level headline colors (`headline_highlight`,
  `mep.org.headlinehl`) and per-keyword TODO-state colors
  (`todo_highlight`/`todo_keyword_colors`, `mep.org.todohl`) sit on top
  of that same static query as their own extmarks instead — real
  org-mode's own look (TODO red, DONE green) by default, and fully
  configurable: `todo_keyword_colors = { TODO = 'DiagnosticError', DONE =
  'DiagnosticOk' }` links a keyword to any real highlight group, and a
  `todo_keywords` entry with no color there cycles through a 6-color
  fallback palette instead. Priority
  cookies (`[#A]`) highlight as `@constant` — matched by literal text
  since the grammar has no dedicated priority node, same tradeoff as the
  TODO/DONE matching above (a title word that happens to look exactly
  like `[#A]` would also light up). Links get no special color (same
  reason: no grammar node), but a bare `[[target]]` in an active planning
  entry, and any active/inactive timestamp, already highlight generically
  via the grammar's own `timestamp` node — confirmed against the real
  compiled parser that an *inactive* `[...]` timestamp only parses as a
  proper node on its own planning line, not inline in body text (a
  grammar limitation, not something fixable from this project's query
  file).
- **Poly mode** (`mep.org.polyglot`) — a single org file mixing any number
  of `#+begin_src <lang> ... #+end_src` blocks gets real syntax
  highlighting *and* real LSP features for each one, in its own language,
  active by default. Two independent mechanisms, both automatic:
  - **Highlighting** is tree-sitter language injection
    (`queries/org/injections.scm`): each block's body is parsed and
    highlighted with *that language's own* installed parser (the same
    ones `mep.treesitter`'s curated registry already installs), laid
    directly on top of `org`'s own highlighting the moment it's active —
    not gated by any `polyglot` option at all, only by `highlight` above
    and by that language's parser actually being installed (a language
    with none just doesn't highlight, the same graceful-miss as anywhere
    else in this project). Uses only built-in query predicates
    (`#eq?`/`#any-of?`/`#lua-match?`/`#set!`) to normalize a block's
    language token (`C++`/`cpp`, `sh`/`bash`, a handful of common
    alternate capitalizations) to its real parser name — deliberately not
    a custom Lua predicate, since this query file is discovered and run
    by Neovim's own highlighter as soon as *any* `org` buffer highlights
    (`mep.treesitter` can trigger that on its own, without
    `mep.org.setup()` ever running), and an unregistered custom directive
    is a hard error there, not a graceful no-op. Since `mep.treesitter`'s
    own `ensure_installed` only ever installs its curated registry as a
    *whole* (or an explicit subset you name up front) — it has no way to
    know an org file's src blocks are about to need `ruby`/`go`/etc — each
    org buffer additionally installs (in the background, the same
    `mep.treesitter.install` pipeline, a no-op for anything already
    available) a parser for every language its own blocks actually use
    (`mep.org.polyglot.ensure_language_parsers`), forcing a re-highlight
    once each one lands. This is what actually makes highlighting work
    out of the box even with `mep.treesitter.setup({ ensure_installed =
    false })` (`scripts/try_init.lua`'s own choice, "too heavy for a quick
    session") — a block in a language with no curated parser (`perl`, `R`)
    still just doesn't highlight, same graceful miss as elsewhere.
  - **LSP** (real hover/definition/references/rename/diagnostics/manual
    completion, sourced from each language's own server while the cursor
    is inside its block) works by keeping one hidden real buffer per
    language (a "shadow buffer", the same trick otter.nvim popularized)
    in sync with that language's block bodies, laid out at the *same
    line numbers* as the org buffer so no position translation is ever
    needed — just URI rewriting on the way back for anything that
    returns a location. Each shadow buffer's `filetype` is set to the
    language's own Neovim filetype and nothing else; whatever server(s)
    `mep.lsp` (or your own LSP config) already registered via `vim.lsp.
    enable` for that filetype attach on their own, through Neovim's
    normal `FileType` autostart — this module never launches a server
    itself, and (like `mep.lsp` itself) never installs one either: a
    language with no server actually on `PATH` just gets no LSP features
    inside its blocks, the same silent-until-you-install-it contract
    `mep.lsp`'s own README section describes. A language's shadow buffer
    (and therefore its real server, if one's registered) is only ever
    created the first time the cursor actually lands inside one of its
    blocks — never proactively for every language a buffer's blocks use
    the moment it's opened, since setting a shadow buffer's `filetype` is
    exactly what triggers that autostart: eager creation would silently
    start a real server for every src-block language in the buffer
    whether or not you ever visit it (worse than merely wasteful for a
    server with side effects of its own — `serve-d`'s bundled DCD
    prompting to download an update the moment its shadow buffer's
    filetype was set, before the cursor had moved once, is what surfaced
    this in the first place). On a system with nothing
    globally on `PATH` by default (NixOS being the standing example — see
    this repo's own `flake.nix` `devShells.default`, which lists a server
    for every `mep.lsp.servers` entry precisely so `nix develop` gives you
    a working poly-mode LSP session to try this in), that means *some*
    project-local shell has to put the servers you want there yourself.
    A shadow buffer also needs `vim.lsp.enable`'s autostart to consider it
    at all, which — confirmed against Neovim's own source — flatly skips
    any buffer whose `'buftype'` isn't empty or `'help'`; each shadow
    buffer is therefore a real (`buftype=''`), never-actually-written-to-
    disk buffer (`'modified'` force-cleared after every sync, a
    `BufWriteCmd` autocmd no-ops any stray `:w`) rather than the more
    obvious `'nofile'`, which would otherwise never get a client at all.
    A compiled language's block body (C/C++/Rust/Go) *can* be bare
    statements rather than a complete program — a shadow buffer's
    language server would otherwise see top-level statements outside any
    function for one of these (confirmed empirically against clangd on
    exactly this shape: it doesn't just flag the bare call, it mis-parses
    the whole thing as an implicit-`int`-return function declaration —
    "type specifier missing, defaults to 'int'"). `:main yes` opts a
    block into exactly that: real org-babel's own `:main` header-arg
    wraps a bare-statement block at *execution* time only, and this same
    flag drives the shadow buffer's equivalent, a minimal entry-point
    wrapper (`int main(void) { ... return 0; }`/`fn main() { ... }`/
    `package main; func main() { ... }`) added around it. The *default*
    (no `:main` at all, or an explicit `:main no`) assumes the opposite —
    a self-contained program that already defines its own entry point —
    since that's the common case for a block worth pasting into a src
    block at all; deliberately not execution-accurate either way (no
    `:includes` handling: `#include`/Go's `import` need their own
    physical line, with no legal way to share one with the wrapper). For
    rust/go/php, a shadow buffer still merges every block of one language
    into a single file, so only one wrapped (`:main yes`) block per
    language per org file is supported — a second one collides on the
    entry point, the same "only one real program at a time" constraint
    real org-babel's own execution model already has. **c/cpp are the
    exception**: each block gets its own shadow buffer (one per block,
    not one shared per language), so any number of `:main yes` C/C++
    blocks in one file work independently — see the `compile_commands.
    json` paragraph below for why. Two servers
    specifically (confirmed empirically) need more than a client
    attaching to make any of this work at all: rust-analyzer shells out to
    `cargo metadata`/`cargo check` for its own workspace discovery, and
    gopls behaves the same way for `go.mod` — a client attaches fine
    either way, but every feature silently returns nothing without one. A
    real `Cargo.toml`/`go.mod` (declaring the shadow file as a `[[bin]]`
    where that's needed) is written next to the shadow buffer's own path
    the first time it's created, and — the one exception to shadow buffer
    content never touching disk — that content is *also* mirrored to the
    same real file on every sync, since `cargo check` validates the
    on-disk path independently of whatever the LSP client already told it
    about the open buffer. A blanket `.gitignore` (`*`) written alongside
    keeps all of it out of your own repo; the whole `.mep-polyglot/`
    scaffold directory is removed again when the org buffer closes.
    **c/cpp (clangd) needs a `compile_commands.json`** to know how to
    parse a translation unit at all — without one, `#include <iostream>`
    and everything downstream just fails to resolve (clangd falls back to
    guessed flags with no system include paths). Rather than scattering
    one across the whole file (clangd's flags are per-file, not
    per-line-range — a single shared compile database entry couldn't
    describe several independent little programs correctly anyway), each
    c/cpp block gets its own shadow buffer *and* its own scratch directory
    under `stdpath('cache')/mep-polyglot/<bufnr>/<c|cpp>/block_<lnum>/`
    (an OS cache directory, deliberately not next to your project at all
    — nothing to `.gitignore`, nothing to see in `ls`). clangd attaches
    with no flags at all the first time you visit a block, same as always;
    only after you actually run it (`<C-c><C-c>`/`<C-c>e`) does that
    block's own `compile_commands.json` get (re)generated from the exact
    compiler `mep.org.babel.execute` itself resolved. Not a full client
    restart — clangd itself keeps running, still attached to every other
    block — just that one block's own document being properly closed and
    reopened (`vim.lsp.buf_detach_client`/`buf_attach_client`) right after
    a `workspace/didChangeWatchedFiles` notification goes out; confirmed
    empirically that the notification alone doesn't make clangd re-derive
    flags and reparse an already-open document on its own — the
    diagnostics it already computed under the old fallback flags just sit
    there until the document is actually reopened. This still won't
    resolve a *missing*
    `#include` in a synthetically-wrapped (`:main yes`) block's own text
    (a separate, pre-existing limitation — see the `:main yes` paragraph
    above); a self-contained (`:main no`, the default) block that already
    writes its own real `#include`s is fully covered. `mep.lsp` itself
    also appends a `--query-driver=...` flag to clangd's `cmd`, scoped to
    wherever `gcc`/`g++`/`cc`/`c++`/`clang`/`clang++` actually resolve on
    your own `PATH` — needed for clangd to discover the real compiler's
    system include paths at all on a system (NixOS being the standing
    example) where they aren't wherever clangd's own built-in defaults
    expect; skipped entirely if none of those resolve, and never
    overrides a `--query-driver` you've already set yourself.
    `gd`/`gD`/`gr`/`gi`/`K`/`<C-k>`/`<leader>rn`/`[d`/`]d`/
    `<leader>le` (mirroring `mep.lsp`'s own keymap vocabulary) work
    inside a block using that language's client; outside of one, they
    fall through to whatever's attached to the org buffer itself
    (ordinarily nothing, since org has no LSP of its own — real org-mode
    LSPs, if you have one configured, still get a chance there). Manual
    completion is `<C-x><C-o>` (`'omnifunc'`), not autotrigger-as-you-type
    — the org buffer itself never has an attached client for `vim.lsp.
    completion.enable` to hook into, the same tradeoff otter.nvim makes.
    Diagnostics are mirrored onto the org buffer directly (`vim.
    diagnostic.set`), so they show inline over the real text and
    `[d`/`]d`/`<leader>le` need no bridging at all. Set `polyglot = false`
    to turn this off entirely (highlighting is unaffected); `polyglot = {
    keymaps = {...} }` to rebind just the keymaps.
  - **Status widget** (`mep.org.polyglot.status_widget()`) — a
    `mep.chrome`-shaped widget (`{ text = function(ctx) ... end, hl =
    'MepOrgPolyglotStatus' }`, linked to `ModeMsg` by default) showing the
    language of the src block at the cursor (` python `, ` rust `, ...),
    live-updated (a `CursorMoved`/`CursorMovedI` autocmd calls
    `:redrawtabline`, only when the reported language actually changes)
    and empty outside an org buffer or outside any block. Not wired into
    any tabline/statusline automatically — `mep.chrome` has no awareness
    of `mep.org` (or any other library), the same independence every pair
    of mep libraries keeps — compose it into your own config:
    ```lua
    require('mep.chrome').setup({
      tabline = {
        widgets_after = vim.list_extend(
          { require('mep.org.polyglot').status_widget() },
          require('mep.chrome.config').defaults.tabline.widgets_after
        ),
      },
    })
    ```

```lua
require('mep.org').setup({}) -- todo_keywords={'TODO','DONE'}, todo_highlight=true, todo_keyword_colors={TODO='DiagnosticError', DONE='DiagnosticOk'}, highlight=true, fold=true, sort_criteria='alpha', priorities={'A','B','C'}, tags={}, tags_column=77, conceal_links=true, capture_templates={}, agenda_files={}, deadline_warning_days=14, attach_dir='data', polyglot={keymaps={...}}
require('mep.org').setup({ todo_keywords = { 'TODO', 'DOING', 'DONE' }, tags = { 'work', 'home', 'urgent' } })
require('mep.org').setup({
  todo_keywords = { 'TODO', 'DOING', 'WAITING', 'DONE', 'CANCELLED' },
  -- Any keyword left out here (WAITING/CANCELLED) cycles through
  -- mep.org.todohl.LINKS instead — still gets its own distinct color,
  -- just not one you picked.
  todo_keyword_colors = {
    TODO = 'DiagnosticError',
    DOING = 'DiagnosticWarn',
    DONE = 'DiagnosticOk',
  },
})
require('mep.org').setup({ capture_templates = {
  { key = 't', description = 'Task', target = { file = '~/todo.org' }, template = '* TODO %? %a' },
} })
require('mep.org').setup({ agenda_files = { '~/notes/*.org' }, deadline_warning_days = 7 })
require('mep.org').setup({ polyglot = false }) -- no per-language LSP bridging; highlighting still works
```

#### Keymaps inside org buffers

`Mod1` is Alt on Linux/Windows and Option on macOS — see
[Global modifier keys](#global-modifier-keys) under Setup.

| Key                    | Mode   | Action                                        |
|-------------------------|--------|-------------------------------------------------|
| `<C-c><C-n>`            | normal | Next headline                                    |
| `<C-c><C-p>`            | normal | Previous headline                                |
| `<Mod1-Left>` / `<Mod1-Right>`| normal | Promote/demote the current headline only         |
| `<Mod1-S-Left>`/`<Mod1-S-Right>`| normal | Promote/demote the whole subtree              |
| `<Mod1-S-Up>`/`<Mod1-S-Down>` | normal | Move the subtree up/down among its siblings      |
| `<Mod1-CR>`                | normal | Insert a new sibling headline, enter insert mode |
| `<Mod1-S-CR>`              | normal | Same, pre-filled with the first TODO keyword     |
| `<C-c><C-t>`            | normal | Cycle TODO state (also refreshes ancestor cookies) |
| `<C-c>,`                | normal | Cycle priority cookie (`[#A]` → `[#B]` → `[#C]` → none) |
| `<C-c><C-c>`            | normal | Toggle the checkbox under the cursor (also refreshes ancestor cookies) |
| `<Tab>`                 | normal | Toggle fold under the cursor (`za`)              |
| `<S-Tab>`               | normal | Cycle global visibility (overview/contents/all)  |
| `<C-c>^`                | normal | Sort the current headline's siblings             |
| `<C-c>n` / `<C-c>N`     | normal | Narrow / widen to the current subtree            |
| `<C-c><C-x><C-a>`       | normal | Archive the current subtree                      |
| `<C-c><C-w>`            | normal | Refile the current subtree (via `mep.picker`)    |
| `<C-c>.` / `<C-c>!`     | normal | Insert/edit an active/inactive timestamp at the cursor |
| `<C-c><C-s>` / `<C-c><C-d>` | normal | Schedule / set deadline on the current headline |
| `<C-a>` / `<C-x>`       | normal | Adjust the timestamp under the cursor by `[count]` days (a week: `7<C-a>`); falls back to Neovim's native increment/decrement off a timestamp |
| `<C-c><C-q>`            | normal | Fast tag-selection popup (single-letter toggles from `config.tags`) |
| `<C-c><C-o>`            | normal | Follow the link under the cursor                 |
| `<C-c><C-l>`            | normal, visual | Insert a link (visual: wraps the selection as description) |
| `<C-c>l`                | normal | Store a link to the current headline for later `<C-c><C-l>` recall |
| `<C-c>>` / `<C-c><`     | normal | Indent / outdent the list item under the cursor (with its continuation lines) |
| `<C-c>#`                | normal | Renumber the ordered list at the cursor          |
| `<C-c>/`                | normal | Sparse-tree search (asks tag or TODO state, then folds to matches) |
| `<C-c><C-x>p`           | normal | Set a property (prompts key then value)          |
| `<C-c><C-x><C-i>` / `<C-c><C-x><C-o>` | normal | Clock in / clock out         |
| `<C-c><C-x><C-r>`       | normal | Insert/refresh a clock-table report              |
| `<C-c>c`                | normal, visual | Capture (picker over `config.capture_templates`; visual: selection becomes `%i`) |
| `<C-c>a`                | normal | Agenda (prompts for day/week/todo/tags view across `config.agenda_files`) |
| `<C-c>e` / `<C-c>E`     | normal | Execute the src block at the cursor / tangle every `:tangle`-targeted block in the buffer |
| `<C-c><C-x>f`           | normal | Footnote action: jump to a reference's definition (or back), else insert a new footnote |
| `<C-c><C-x>i`           | normal | Get-or-create an `:ID:` property on the current headline |
| `<C-c><C-a>`            | normal | Attach a file to the current headline (`config.attach_dir`) |
| `<C-c><C-e>`            | normal | Export (prompts ascii/markdown/html, writes next to the source file) |
| `<Tab>`                 | insert | Expand an easy template (`<s`, `<e`, `<q`, `<c`, `<v`, `<C`), else normal Tab |
| `<CR>`                  | insert | Continue the list item at the cursor, else a plain newline |
| `gd` / `gD` / `gr` / `gi` / `<leader>lt` | normal | Poly mode: goto definition/declaration/references/implementation/type-definition, sourced from the src block's own language server (`mep.org.polyglot`, `config.polyglot.keymaps`) |
| `K` / `<C-k>`           | normal (insert for `<C-k>`) | Poly mode: hover / signature help |
| `<leader>rn`            | normal | Poly mode: rename (prompts a new name) |
| `[d` / `]d` / `<leader>le` | normal | Poly mode: previous/next diagnostic, show diagnostic float (diagnostics are mirrored onto the org buffer directly) |
| `[e` / `]e`             | normal | Poly mode: previous/next diagnostic with severity ERROR |

All configurable via `require('mep.org').setup({ keymaps = {...} })` —
see `lua/mep/org/config.lua` for the full defaults. `mep.org.polyglot`'s
own keymaps (the poly-mode row above) are a separate table,
`config.polyglot.keymaps` — see `require('mep.org').setup({ polyglot = {
keymaps = {...} } })` above. The capture popup
itself has two fixed (not configurable) keymaps, matching real
org-mode's own capture-buffer bindings: `<C-c><C-c>` files the entry and
closes, `<C-c><C-k>` aborts without filing.

### `mep.markdown` — visual styling for markdown buffers

Distinct highlighting for markdown structure, layered on top of
`mep.treesitter`'s own install+activate pipeline (installs the
`markdown`/`markdown_inline` parsers if missing, then starts
highlighting for any `markdown`-filetype buffer, present or future) —
plus a sign-column marker per heading line, box-drawn GFM tables, and
shaded fenced-code-block backgrounds.

- **Headers** — `@markup.heading.1`..`.6` (H1-H6) each linked to a
  distinct group (`Title`/`Function`/`Keyword`/`Identifier`/`Type`/
  `Comment` respectively), so nesting depth is visible at a glance
  instead of every heading level rendering the same.
- **Emphasis** — `@markup.strong`/`@markup.italic` (bold/italic) colored
  like `Constant`/`String` on top of the weight your theme already gives
  them.
- **Gutter** (`mep.markdown.gutter`) — one sign per ATX heading line
  (`#` .. `######`), showing its level as a circled digit by default
  (`①`-`⑥`, `config.gutter_symbols`) in that level's own heading color;
  kept live (debounced) as the buffer changes, mirroring `mep.git.
  gutter`'s own attach/detach lifecycle.
- **Tables** (`mep.markdown.tables`) — re-renders GFM pipe tables
  (`| a | b |` / `|---|---|`, including `:---`/`:---:`/`---:` column
  alignment) as real box-drawn tables: aligned columns, `┌─┬─┐`/
  `├─┼─┤`/`└─┴─┘` borders, bold header cells. Pure line-pattern
  detection (`mep.markdown.tables.find_tables`), and pure *display* —
  it's all overlay extmarks (`virt_text_pos = 'overlay'` for each row,
  `virt_lines` for the synthetic top/bottom border), so the buffer's
  actual text is untouched plain markdown underneath. The row the
  cursor is on is left un-overlaid so you can see and edit exactly what
  you're typing; everything else reflows the moment the cursor moves
  off it.
- **Code blocks** (`mep.markdown.codeblocks`) — shades every line of a
  fenced (` ``` `/`~~~`) code block, fence lines included, with
  `MepMarkdownCodeBlock` (linked to `CursorLine` by default) so code
  reads as a distinct block instead of blending into surrounding prose.
- **Checkbox toggling** (`mep.markdown.checkbox`, `<C-c><C-c>` by
  default) — GFM task-list checkboxes (`- [ ]`/`- [x]`, and their
  numbered-list equivalent `1. [ ]`), mirroring `mep.org.checkbox`.
  Real org-mode's own `<C-c><C-c>` convention, free to reuse here since
  markdown has no babel-execute dual purpose to disambiguate from the
  way `mep.org`'s own `<C-c><C-c>` does.
- **Folding** (`mep.markdown.fold`, `<Tab>`/`za` to toggle) —
  ATX-heading-depth folding, mirroring `mep.org.fold`: a heading's fold
  swallows its body text and every shallower-nested heading's own
  content as one block; a fenced code block gets its own nested fold one
  level deeper, foldable independently of the rest of its section.
- **Link/emphasis concealment** (`mep.markdown.linkconceal`) — hides
  raw `[text](url)`/`**bold**`/`*italic*`/`__bold__`/`_italic_`/
  `~~strike~~` syntax, showing only the rendered text, mirroring `mep.
  org.linkconceal`. Pure line-pattern matching (not tree-sitter,
  deliberately — same "works immediately, even before/without the
  parser installed" reasoning `mep.org`'s own structural modules
  document), a known simplification of full CommonMark emphasis-
  flanking rules (escaped `\*`, code spans, and nested emphasis aren't
  specially handled). Needs `'conceallevel'` >= 2, set automatically on
  windows showing an activated buffer.
- **Front matter** (`mep.markdown.frontmatter`) — recognizes a YAML
  (`---`)/TOML (`+++`) block at the very top of the file (real static-
  site-generator convention) and shades it with `MepMarkdownFrontmatter`
  (linked to `ColorColumn` by default), the same overlay-extmark
  shading `mep.markdown.codeblocks` uses for fenced code.

```lua
require('mep.markdown').setup({}) -- highlight=true, headers=true, emphasis=true, gutter=true, gutter_symbols={'①',...,'⑥'}, tables=true, code_blocks=true, checkbox=true, fold=true, conceal=true, frontmatter=true
```

Header/table/code-block/frontmatter groups use `default = true` (only
claims a group nothing else has already defined — same convention as
every other `MepXxx` group in this codebase), so a colorscheme that
sets its own `@markup.heading.1`..`.6`/`MepMarkdownTable*`/
`MepMarkdownCodeBlock`/`MepMarkdownFrontmatter` wins; emphasis always
overrides, layering color onto whatever bold/italic weight is already
there. No dedicated toggle command — like `mep.org`, it activates
automatically via `FileType`.

### `mep.whichkey` — a popup showing what's bound under a prefix key

Real which-key.nvim's core idea (press a prefix, see what's next), built
without a dependency on it: no separate registration step — anything
already bound via `vim.keymap.set` (this project's own libraries, or
your own config) shows up automatically, since `mep.whichkey.registry`
introspects real keymaps (`nvim_get_keymap`/`nvim_buf_get_keymap`)
rather than keeping its own list. A mapping's `desc` becomes its label;
without one, its string `rhs` is shown instead (e.g.
`<cmd>MepFindFiles<cr>`), or a generic placeholder for a bare callback
with neither — this project's own `mep.org`/`mep.filetree` keymaps all
carry a `desc` already, so they show up with real labels out of the box.

`config.triggers` (default `{'<leader>'}`) become keymaps (in every
`config.modes`, default `{'n'}`) that open the popup. Pressing a listed
key either runs its mapping directly (a leaf) or descends into another
popup for the next level (a group — shown as `+N mapping(s)`, real
which-key's own "submenu" concept, e.g. pressing `<leader>` then `f`
when both `<leader>ff` and `<leader>fg` exist); `<Esc>`/`q` dismiss
without doing anything. A single unambiguous leaf under a prefix runs
immediately with no popup at all.

`config.position` controls where the popup appears: `'bottom'`
(default — real which-key.nvim's own default look: spans the full
editor width, anchored just above the command line, entries laid out in
a column-major grid — fill down a column before starting the next — to
make use of that width instead of one cramped list), `'top'` (same, but
anchored at row 0), or `'cursor'` (a compact single column right under
the cursor, this library's original look). `config.border` (default
`'rounded'`) is passed straight through to `nvim_open_win`; `'bottom'`/
`'top'` inset their content by 1 cell on every side to keep a non-`'none'`
border's *outer* edge flush with the requested position — pass
`border = 'none'` for a truly edge-to-edge bar.

```lua
require('mep.whichkey').setup({}) -- triggers={'<leader>'}, modes={'n'}, position='bottom', border='rounded'
require('mep.whichkey').setup({ triggers = { '<leader>', ',' } })
require('mep.whichkey').setup({ position = 'cursor' }) -- the original v1 look
```

If `<leader>` is one of your triggers (the default), call
`require('mep.whichkey').setup(...)` — or `require('mep').setup(...)`,
which already orders this correctly — *after* whatever sets
`vim.g.mapleader` (`mep.sanity.setup`, if you use it): like any
`<leader>`-using keymap, Neovim resolves `<leader>` to the current
`mapleader` when the mapping is *defined*, not when it's later pressed.

**Scope note**: no debounce/typeahead-skip like real which-key.nvim's
optional delay (type a whole sequence fast enough and its popup never
appears) — this one always shows immediately once a trigger fires; see
`lua/mep/whichkey/whichkey.lua`'s header comment for why that tradeoff
was made. A key that's *both* a complete binding and a prefix of longer
ones (genuinely ambiguous — none of this project's own keymaps do it)
is shown as a group only; its own direct binding becomes unreachable
through the popup, though still reachable by typing the full sequence
without ever triggering mep.whichkey.

### `mep.sidebar` — build your own side (or top/bottom) panel

A generic building block for a persistent panel of clickable,
highlightable, hoverable widgets grouped into collapsible sections —
`mep.activitybar` (below) is the flagship example of what it's for, not
a special case bolted on: its button bar and all three of its panels are
just `mep.sidebar` instances built through the same public API described
here.

```lua
local sidebar = require('mep.sidebar').new({
  title = 'Build',
  position = 'right',                -- 'left' | 'right' | 'top' | 'bottom'
  width = 40,                        -- left/right size ('height' for top/bottom)
  animate = true,                    -- slide into/out of view
  float = false,                     -- true: a floating "popup buffer", not a real split
  -- border = 'rounded',             -- float only
  -- edge_offset = 0,                -- float only: stack next to another fixed edge element
  -- focus = true,                   -- false: leave the cursor in whatever window was current
  sections = {
    {
      id = 'actions',
      title = 'Actions',             -- title = false: no header, no indent — just buttons
      collapsed = false,
      widgets = {
        {
          id = 'run',
          text = 'Run build',
          icon = '▶',
          hl = 'DiagnosticOk',       -- any highlight group
          tooltip = 'Click to run the build', -- shown on CursorHold, or a function(widget)
          on_click = function(widget, sb) ... end,
        },
      },
    },
  },
})

sidebar:open()    -- sidebar:close(), sidebar:toggle(), sidebar:is_open()
sidebar:set_sections(new_sections)     -- replace content and re-render
sidebar:collapse_section('actions')    -- toggle (or force: pass true/false)
sidebar:resize(10)                     -- grow/shrink by N columns/rows
```

Two window styles, `opts.float`: a real split by default (like
`mep.filetree`'s single panel, participates in normal window layout,
reflows neighboring windows), or a floating window instead (`opts.float
= true` — flush against `position`'s edge, spanning the full opposite
dimension, entirely independent of other windows: nothing resizes to
make room for it and it doesn't get squeezed by anything else either —
`mep.activitybar`'s own choice, "a popup buffer, not a normal one").
Unlike `mep.filetree`, more than one `mep.sidebar` instance can be open
at once regardless of style (each `new(...)` is independent, `mep.
picker`'s own `Picker.new(...)`/`Picker:method()` object pattern) — a
floating one that should stack *next to* another already sitting on the
same edge (rather than underneath/overlapping it) needs `edge_offset`
set to that other one's on-screen footprint (`mep.sidebar.border_pad(
border)` plus its width — `mep.activitybar` computes this for its own
panels relative to its bar). `opts.focus` (default `true`) is whether
`open()` actually leaves the cursor in the new window — `false` hands
it straight back to whichever window was current before opening (`mep.
git.sidebar`'s own choice: a status panel you glance at without
interrupting whatever you were typing in your actual buffer; switch
into it, e.g. `<C-w>w`, when you want to use its keymaps). "Whichever
window was current" specifically means the last *non-sidebar* one, not
just whatever's current right when `open()` runs — clicking a widget in
one Sidebar (e.g. one of `mep.activitybar`'s own icon buttons) moves
real focus into that Sidebar's own window an instant before the
resulting `on_click` fires, so a click-driven `open()`/`close()` still
resolves back to the real window underneath both, not the sidebar that
was clicked through. Default keymaps inside a sidebar buffer
(all overridable per-instance via `opts.keymaps`): `<CR>` activates the
widget/section header under the cursor (a section header toggles its
own collapse state); a real mouse click (`<LeftRelease>`) does the same;
`q` closes; `+`/`=` and `-` resize. `config.border` (float only)/
`animate_ms`/`animate_steps`/`resize_step`/`min_size` are all
configurable too — see `lua/mep/sidebar/config.lua` for the full
defaults.

```lua
require('mep.sidebar').setup({}) -- position='right', width=30, height=15, animate=true, float=false, border='rounded', edge_offset=0, focus=true
```

**Scope notes**: resizing is keymap-driven (`+`/`-`, or `:resize(delta)`),
not mouse-drag — there's no reliable way to detect a drag across a
window border from plain Neovim APIs. "Animation" is a ramp of the
window's width/height across a few timer ticks (`mep.core.util.
debounce`'s own timer idiom, applied to `nvim_win_set_width`/
`set_height` instead) — about as close to real animation as a
character-grid terminal UI gets, not pixel-smooth. Custom fonts aren't
attempted at all — that's a terminal-level concern outside what any
Neovim plugin can control.

### `mep.notify` — nvim-notify/noice-style toast popups, plus a dismissible history panel

Hooks `vim.notify` itself (`setup()` installs this automatically), so
any notification from anywhere — this project's own libraries, your
own config, another plugin — shows up without any extra wiring, the
same "introspect what's really there" approach `mep.whichkey` takes for
keymaps. Every call becomes two things at once: a small, auto-
dismissing **popup toast**, and a permanent entry in a scrollable
**history panel** you can review and individually delete.

Toasts stack in a screen corner (`config.position`, default
`'top-right'`), newest closest to the corner, older ones pushed away as
more arrive — capped at `config.max_visible` (default 5; past that, the
oldest is closed immediately to make room, not queued). Each is colored
and iconed by level (`MepNotifyError`/`Warn`/`Info`/`Debug` highlight
groups, linked to Neovim's own `Diagnostic*` groups by default — plain
Unicode glyphs `✗ ⚠ ℹ ·`, not Nerd Font codepoints, so they render
correctly with no special font required) and auto-dismisses after
`config.timeout[level]` ms — errors/warnings linger longer than routine
info/debug noise by default. Reflows instantly (no gap left behind)
whenever one closes, whether by timeout, `:MepNotifyDismiss`, or
`config.max_visible` eviction.

```lua
require('mep.notify').setup({}) -- position='top-right', max_visible=5, max_entries=200
require('mep.notify').setup({ position = 'bottom-left', max_width = 50 })
require('mep.notify').setup({ timeout = { [vim.log.levels.INFO] = 2000 } }) -- shorter for routine info toasts
```

```vim
:MepNotifyPanel     " toggle the standalone history panel
:MepNotifyClear      " clear all notification history
:MepNotifyDismiss     " dismiss every currently-visible toast (history untouched)
```

The history panel (`require('mep.notify').toggle()`, a `mep.sidebar`
instance sized/positioned by its own `config.panel`, independent of
`mep.activitybar`'s own sizing) lists every entry newest-first, colored
the same way as its toast — click one (or press `d`/`x` on it) to
dismiss just that entry, "Clear all" (or `C`) to empty the whole list.
Capped at `config.max_entries` (default 200, oldest dropped first).

`mep.activitybar`'s own notifications button (below) is just a second,
differently-sized `mep.sidebar` view onto this exact same entry list —
not a separate history or a second `vim.notify` hook — so dismissing an
entry from either place removes it everywhere, the same "one shared
data source, several attached sidebar views" pattern `mep.git`'s own
dock/split/activitybar panel already uses.

**Scope note**: no click-to-dismiss on the toasts themselves (they're
`focusable = false`, purely transient) — only the history panel supports
manual per-entry deletion. No message deduplication/merging (a "same
error 50 times" spam scenario shows 50 toasts/entries, not one counter)
— not attempted, matching this feature's actual ask over a fully
general notification-management system.

### `mep.activitybar` — a notifications/todo/tests/git button bar, built on mep.sidebar

A slim, persistent, icon-only button column (`config.position`, default
`'right'`; each button's label becomes its hover tooltip, not on-screen
text — there's no room for it), sized to exactly fit the widest
configured button icon (`vim.fn.strdisplaywidth`, so a double-width
emoji like the default 🔔 counts for 2 columns, not 1 — never a fixed
guess, and never a column wider than it needs to be) — that toggles
four flyout panels, each a
`mep.sidebar` instance that slides into view next to it. Both the bar
and its panels are real floating windows (`mep.sidebar`'s `float =
true`), flush against the edge and stacked adjacent to each other
(`edge_offset`) rather than real splits — "popup buffers" that don't
disturb, or get disturbed by, any other window. The bar itself never
takes focus on open (`focus = false` — it opens automatically on
startup, `config.auto_open`, real `mep.dashboard.config.auto_open`'s own
idea, and shouldn't pull the cursor away from the dashboard opening
alongside it); its panels do (`mep.sidebar`'s own default) *except* the
git one, which — like `mep.git.sidebar`'s own dock/split — doesn't
either, a status panel you glance at rather than one that interrupts
whatever you were typing. Switch into any of them (e.g. `<C-w>w`, or
just click) to use their keymaps.

Every button/action icon — the four bar buttons, plus the todo panel's
own "Add"/"Clear done" and the tests panel's own "Run tests" — comes
from `mep.icons`'s own curated UI icon set (`require('mep.icons').
get_ui_icon(...)`, see that library's own section above), so `require(
'mep.icons').setup({ style = 'ascii' })` restyles this bar the same way
it restyles `mep.filetree`. Set a `buttons` entry's own `icon` field
(e.g. `{ id = 'notifications', icon = '🔕' }`) to override just that one
regardless of style.

- **Notifications** — a view onto `mep.notify`'s own entry list (see
  above), not a separate history of its own — `setup()` installs `mep.
  notify`'s `vim.notify` hook, which also drives that library's own
  popup toasts. Click an entry (or press `d`/`x`) to dismiss it, "Clear
  all" (or `C`) to empty the list — from here or `mep.notify`'s own
  standalone panel, since both show the same shared list.
- **Todo** — "Add todo..." prompts via `vim.ui.input`; click an item to
  toggle it done (`[ ]`/`[x]`, done items dimmed via the `Comment`
  highlight group); "Clear done" removes every done item. Persisted as
  JSON to `config.todo.persist_path` (default `stdpath('data') ..
  '/mep_activitybar_todo.json'`) so it survives a restart — unlike the
  notifications panel's deliberately ephemeral, session-only entries.
- **Tests** — "Run tests" shells out to `config.tests.cmd` (this
  project's own `{'busted'}` by default — point it at whatever your
  project actually uses, e.g. `{'npm', 'test'}`) via `mep.core.job`,
  shows the summary line plus one widget per failure, and clicking a
  failure opens a popup with its full captured reason.
- **Git** — `mep.git.sidebar`'s own status/hunks content and
  commit/stage/unstage/discard/refresh keymaps, just anchored next to
  this bar instead of `mep.git.sidebar.toggle_dock()`/`.toggle_split()`'s
  own presentations — all three (this panel, the dock, the split) are
  the same underlying content and stay in sync with each other, not
  three independent copies of it. See `mep.git` below for what it shows
  and its keymaps.

```lua
require('mep.activitybar').setup({}) -- position='right', panel_width=42, animate=true, float=true, auto_open=false
require('mep.activitybar').setup({ tests = { cmd = { 'npm', 'test' } } })
require('mep.activitybar').setup({ auto_open = true }) -- show the bar automatically on startup instead
```

```vim
:MepActivityBarToggle   " toggle the button bar
:MepNotifications       " toggle the notifications panel (in the activity bar; see also :MepNotifyPanel)
:MepTodo                " toggle the todo panel directly
:MepTests                " toggle the tests panel directly
:MepTestsRun             " run tests without opening the panel first
:MepGitPanel             " toggle the git panel directly
```

Also reachable as plain functions for your own keymaps: `require('mep.
activitybar').toggle_bar()`/`.toggle_panel('notifications' | 'todo' |
'tests' | 'git')`, or drill into a specific panel's own module
(`.notifications`/`.todo`/`.tests`/`.git`) for its full API
(`.notifications` is just `mep.notify`'s own `add(msg, level)`/
`dismiss(id)`/`clear()` — see `mep.notify` above; `todo.add(text)`/
`.toggle_done(id)`, `tests.run()`/`.parse_output(text)`, ...).

**Scope note**: `mep.activitybar.tests.parse_output` is written against
busted's own default terminal reporter output (this project's own test
suite) — a summary line plus `"Failure -> file @ line"`/`"Error -> file
@ line"` blocks. Point `config.tests.cmd` at a different test runner and
its plain-text output won't parse into anything useful; a fully generic
"understand any test framework's terminal output" parser isn't
attempted (see the module's own header comment for the reasoning — write
your own `parse_output` against a machine-readable reporter if you need
one).

### `mep.lsp` — LSP client setup, no lspconfig/mason needed

**Requires Neovim >= 0.11** (`vim.lsp.config`/`vim.lsp.enable`, newer
than this project's own general >= 0.9 baseline) — on anything older,
`setup()` warns and no-ops rather than erroring, the same graceful
degradation `mep.org.link`'s `vim.ui.open` use (needing >= 0.10) already
established.

Registers `mep.lsp.servers.registry`'s curated `cmd`/`filetypes`/
`root_markers` configs (lua_ls, pyright, ts_ls, gopls, rust_analyzer,
clangd, bashls, jsonls, yamlls, marksman, zls, nimlsp, crystalline,
jdtls, kotlin_language_server, haskell_language_server, ocamllsp,
serve_d — the same "curated slice, not nvim-lspconfig's whole catalogue"
tradeoff `mep.treesitter.parsers` already makes for grammars, and
deliberately covering the same languages `mep.org.babel` executes,
wherever a real LSP for one exists at all) via Neovim's own native
`vim.lsp.config`/
`vim.lsp.enable` — activating a server only if its `cmd[1]` is actually
found on `PATH` (`vim.fn.executable`). **No server is ever installed**
(unlike `mep.treesitter`'s parsers, which are — a C compiler + `git
clone` is a uniform install path across every grammar; a language
server's install path is wildly heterogeneous — npm, pip, go install,
cargo, curl+prebuilt binary — with no single zero-dependency mechanism
covering all of them): install the servers you want yourself, however
your package manager of choice wants to.

One server gets a small per-machine augmentation before registration:
`clangd`'s `cmd` has `--query-driver=<dir>/**` appended for every one of
`gcc`/`g++`/`cc`/`c++`/`clang`/`clang++` this machine's own `PATH` actually
resolves (`vim.fn.exepath`, deduped by directory) — without it, clangd
can't discover a real compiler's system include paths on a system (NixOS
being the standing example, but this isn't Nix-specific) where they aren't
wherever clangd's own built-in defaults expect, so `#include <iostream>`
and everything downstream just fails to resolve. Scoped to this machine's
own resolved compiler paths rather than a blanket `--query-driver=**`
(clangd would otherwise execute *any* compiler named in *any*
`compile_commands.json` it finds, in any project you open); skipped
entirely if none of those resolve, and never overrides a `--query-driver`
you've already set yourself via `options.servers.clangd` or a fully custom
`cmd`. See `mep.org.polyglot`'s own section above for the other half of
this — c/cpp org babel blocks generating their own `compile_commands.json`
after you actually run them.

On `LspAttach`, binds the classic `gd`/`gD`/`gr`/`gi`/`K` vocabulary
(`mep.lsp.keymaps` — nvim-lspconfig's own long-standing example config
popularized these; Neovim >= 0.11's own built-in `gr`-prefixed defaults
like `grr`/`gri` still work too, this is an additional, more
traditional set, not a replacement) plus rename/code-action/format/
signature-help/diagnostic-navigation, and turns on native LSP-driven
completion (`vim.lsp.completion.enable` — Neovim's own built-in
completion menu, no separate completion-engine plugin needed) for any
client that actually supports it.

```lua
require('mep.lsp').setup({}) -- enable=true, servers={}, completion=true, diagnostics={...}, keymaps={...}
require('mep.lsp').setup({ enable = { 'lua_ls', 'rust_analyzer' } }) -- only ever activate these two
require('mep.lsp').setup({ servers = { my_server = { cmd = {'my-ls'}, filetypes = {'myft'}, root_markers = {'.git'} } } })
```

| Key | Mode | Action |
|-----|------|--------|
| `gd` / `gD` | normal | Goto definition / declaration |
| `gr` / `gi` | normal | References / goto implementation |
| `K` | normal | Hover |
| `<C-k>` | normal, insert | Signature help |
| `<leader>rn` | normal | Rename |
| `<leader>ca` | normal, visual | Code action |
| `<leader>lf` | normal | Format |
| `<leader>lt` | normal | Goto type definition |
| `<leader>le` | normal | Show the diagnostic under the cursor |
| `[d` / `]d` | normal | Previous/next diagnostic |
| `[e` / `]e` | normal | Previous/next diagnostic with severity ERROR |

All configurable via `require('mep.lsp').setup({ keymaps = {...} })` —
see `lua/mep/lsp/config.lua` for the full defaults. `enable` mirrors
`mep.treesitter.config.defaults.ensure_installed`'s own shape: `true`
(default, every curated-plus-your-own server found on `PATH`), a list
of names (still gated on being found on `PATH`), or `false` (register
configs without auto-activating any of them, so your own
`vim.lsp.enable(name)` calls still work). `:MepLspInfo` shows which
client(s) are attached to the current buffer.

### `mep.completion` — a generic, pluggable completion engine

Debounced multi-source completion merged into **Neovim's own native
insert-mode completion popup** (`vim.fn.complete()`) — no custom
floating-window UI of its own. `<C-n>`/`<C-p>` to navigate, `<C-y>` to
accept, `<C-e>` to abort are all Neovim's own built-in insert-mode
completion keys, already there for free once the engine populates the
menu; `<C-Space>` (configurable) manually invokes it right now,
regardless of `min_chars`.

Typing (debounced by `debounce_ms`) still opens the popup on its own by
default (`auto_trigger = true`; set `false` to only ever open it via
`keymaps.trigger`), but nothing is written into the buffer until you
explicitly press `<C-y>` — the engine applies `completeopt = { 'menu',
'menuone', 'noinsert' }` (configurable) while enabled, restoring
whatever `'completeopt'` held beforehand on `disable()`. Without
`noinsert`, Vim's default ins-completion behavior auto-inserts the top
match into the buffer as you keep typing, which reads as completion
"happening automatically" instead of a suggestion you accept.

Four built-in sources, queried together and merged (first-listed
source wins a duplicate `word`):

- **`lsp`** — queries every LSP client attached to the buffer that
  supports `textDocument/completion`, via Neovim's own
  `vim.lsp.get_clients()` — needs no direct coupling to `mep.lsp`
  specifically, any client `mep.lsp` (or anything else) started shows up
  automatically. If you use both libraries together, pass `lsp = {
  completion = false }` to `mep.lsp.setup()` — otherwise its own native
  `vim.lsp.completion.enable` hookup *and* this source both trigger LSP
  completion independently, fighting over the same popup. Inside a
  `#+begin_src <lang> ... #+end_src` block in an org buffer with
  `mep.org`'s poly mode active (see above), completions come from *that
  language's* own attached client instead — the org buffer itself never
  has one — via the same shadow-buffer bridge poly mode's own hover/
  definition/etc. requests use; this is a soft, optional dependency
  (`mep.completion` stays fully functional without `mep.org` loaded at
  all).
- **`buffer`** — the current buffer's own keyword-shaped tokens matching
  the prefix (Vim's own `<C-n>`/`<C-p>` keyword completion, folded into
  the unified popup) — always available, no external tool or LSP client
  needed.
- **`path`** — filesystem entries, once the text right before the cursor
  looks like `/some/dir/partial-name`.
- **`snippet`** — `mep.snippet`'s own registered per-filetype triggers
  (see that library's own section above) — a soft, optional dependency
  the same way `lsp` is soft on `mep.org` (`mep.completion` stays fully
  functional without `mep.snippet` loaded at all).

```lua
require('mep.completion').setup({}) -- sources={'lsp','buffer','path','snippet'}, debounce_ms=80, min_chars=1, max_items=50, auto_trigger=true
require('mep.completion').setup({ sources = { 'buffer' } }) -- no LSP/path/snippet, just buffer words
require('mep.completion').setup({ auto_trigger = false }) -- only open the popup via <C-Space>
```

Add your own source by extending `require('mep.completion').sources`
with a module exposing `complete(ctx, callback)`: `ctx` is `{ bufnr,
win, lnum, col, line, prefix, startcol }` (`prefix` is the keyword
characters immediately before the cursor); call `callback(items)` —
synchronously or later, doesn't matter which — with a list of
`complete-items`-shaped tables (`:help complete-items`: `word`, `abbr`,
`kind`, `menu`, `info`, ...). `mep.completion.sources.buffer` is a good
reference for the simplest possible (fully synchronous) source;
`.lsp` for an asynchronous one.

**Scope notes**: `lsp` uses `item.insertText or item.label` against a
simple keyword-prefix replacement range, not the item's own (possibly
different) `textEdit` range — adequate for the common case, not a full
LSP `textEdit` implementation. Snippet-shaped `insertText`
(`insertTextFormat = Snippet`) and `snippet` source items both carry
their body along as a `user_data` marker; accepting either still inserts
that word as plain text first (`vim.fn.complete()`'s own behavior,
nothing to hook mid-accept), then `mep.completion.engine`'s own
`CompleteDone` handler swaps it for the real tabstop expansion via
`mep.snippet.expand` — a soft dependency, this all still no-ops cleanly
if `mep.snippet` isn't loaded. `path` is keyed off the *same*
keyword-shaped prefix every other source uses rather than a separate
path-shaped one — see the module's own header comment for why that
turns out not to be a limitation in practice.

### `mep.url` — find and open URLs in any buffer

`gx` opens the URL under the cursor — this **overrides Neovim's own
built-in `gx` default** (`vim.ui.open`, Neovim >= 0.10): an enhancement
of it, not a conflict, with a graceful fallback notification on older
Neovim where `vim.ui.open` doesn't exist yet. `gX` lists every URL in
the current buffer via `mep.picker` and opens whichever one you pick.

```lua
require('mep.url').setup({}) -- keymaps: open={'gx'}, pick={'gX'}
```

Pure line-pattern matching (`find`/`find_at_col` mirror `mep.org.link`'s
own shape) — handles `http(s)://`, other `scheme://` URLs (including a
multi-character scheme like `git+ssh://`), and `mailto:`, trimming
trailing sentence punctuation (`see https://x.com.` doesn't pull in the
period) and never including surrounding parens/brackets/quotes (a
markdown link `[text](https://x.com/page)` or a parenthesized
`(https://x.com)` both extract cleanly). `find_all(bufnr)` (what `gX`'s
picker is built on) and `open(url)` are both plain functions too, for
your own keymaps/commands. `:MepOpenUrl`/`:MepUrls` do the same as
`gx`/`gX` as commands.

### `mep.git` — gutter signs, hunk actions, and a status panel

A git gutter (`mep.git.gutter`) plus a status panel (`mep.git.sidebar`,
built on `mep.sidebar`) sharing the same underlying hunk data.

The gutter attaches to any normal, file-backed buffer inside a git repo
(`BufEnter`/`BufReadPost`), diffing the buffer against `config.options.
base` — `'HEAD'` by default, so every uncommitted change gets a sign
whether it's staged or not; set it to `'index'` to diff against the
staged blob instead (only unstaged changes show, gitsigns' own default),
or any other revision (`'HEAD~1'`, a sha, a branch). Diffing is Neovim's
own built-in `vim.diff()`, not a shelled-out `git diff` — debounced on
`TextChanged`/`TextChangedI`/`BufWritePost`. Sign-column markers: `+`
added, `~` changed, `_`/`‾` deleted (all configurable,
`mep.git.config.defaults.signs`). Buffer-local keymaps: `]c`/`]g` and
`[c`/`[g` jump to the next/previous hunk (wrapping around);
`<leader>hs`/`<leader>hr`/`<leader>hp` stage/reset/preview the hunk under
the cursor. `reset_hunk` edits the buffer directly (no git call — it's
just restoring locally-known text); `stage_hunk` builds a minimal,
zero-context patch (`mep.git.diff.build_patch`) and feeds it to `git
apply --cached --unidiff-zero` over stdin.

The status panel shows two sections — changed files (staged/unstaged/
untracked, from `git status --porcelain`) and the current file's hunks —
and opens three ways, all the same content, kept in sync with each
other: `mep.git.sidebar.toggle_dock()` (a floating panel flush against
an editor edge, `mep.activitybar`'s own style), `.toggle_split()` (a
real split, "pops up as a split in the current buffer", `mep.filetree`'s
own style — opening one of these two closes the other), or as a fourth
button/panel in `mep.activitybar` itself (`mep.activitybar.git`, see
above — independent of the dock/split, can be open at the same time as
either). None of the three steal focus on open (`mep.sidebar`'s own
`focus = false` — a status panel you glance at without interrupting
whatever you were typing; switch into it, e.g. `<C-w>w`, to use its
keymaps). `<CR>` opens the file/hunk under the cursor, `q` closes (both
`mep.sidebar`'s own built-ins); on top of those, `R` refreshes, `c` swaps
the panel into a real, editable `gitcommit`-filetype buffer to compose a
commit message in — `ZZ` commits it and returns to the status view (Vim's
own write-and-quit convention, the same key a real `git commit` editor
session uses), `ZQ` cancels without committing — `s`/`u` stage/unstage
the file under the cursor, `X` discards its changes after a confirm
prompt (all configurable, `mep.git.config.defaults.sidebar.keymaps`).

```lua
require('mep.git').setup({}) -- enable=true, debounce_ms=200, base='HEAD', signs={...}, keymaps={...}, sidebar={...}
vim.keymap.set('n', '<leader>gg', function() require('mep.git').sidebar.toggle_split() end)
vim.keymap.set('n', '<leader>gG', function() require('mep.git').sidebar.toggle_dock() end)
```

(`toggle_sidebar`/`toggle_sidebar_dock`, `<leader>gg`/`<leader>gG` by
default, are also bound directly by `setup()` — the explicit
`vim.keymap.set` calls above are only needed if you want different keys.
`<leader>gg` opens the real split by default — a plain buffer in a plain
window, no floating panel; the docked/floating presentation is the
opt-in `<leader>gG`.)

```vim
:MepGitToggle   " toggle the docked panel
:MepGitSplit    " toggle the split panel
:MepGitPanel    " toggle the activitybar panel
```

**Scope notes**: whole-repo operations (`stage`/`unstage`/`discard`/
`commit`, `mep.git.status`) act on a *path*, not a hunk — hunk-level
staging is the gutter's own `stage_hunk`. No push/pull/branch/log
support — this is a gutter and a status panel, not a full git client.

### `mep.window` — a tiling-window-manager-style layer over Neovim splits

Two independent pieces: a **manual layout** (`mep.window.panes`, on by
default) — recursive `:vsplit`/`:split` panes where each pane can hold
several buffers as "tabs" (Vim itself has no such concept; emulated here
via each pane's own `winbar`) — and a set of **automatic layouts**
(`mep.window.auto`) that rebuild the current tabpage's windows into a
master-stack/vertical/horizontal/square/spiral arrangement *once*, on
demand. Both are Lua-native reimplementations of the same ideas in
`mep-wm` (a separate, real X11/macOS window manager project), adapted to
what a Neovim split tree can actually represent — not a port of its code.

**Manual layout** (`Mod1` = Alt on Linux/Windows, Option on macOS — see
[Global modifier keys](#global-modifier-keys) under Setup):
`<Mod1-v>`/`<Mod1-s>` split the current pane side-by-side/
stacked, loading a shared "empty pane" placeholder buffer into the new
one and selecting it (never deletes a buffer — a scratch buffer is used
purely for "this pane has nothing in it yet"). Opening a real buffer in
a pane any normal way (`:edit`, a picker, `gf`, LSP goto-definition, ...)
registers it as that pane's own tab automatically; `<Mod1-n>`/`<Mod1-p>` (also
`<Mod1-Tab>`/`<Mod1-S-Tab>` — mep-wm binds both to the same two actions too,
not an either/or choice) cycle a pane's active tab. `<Mod1-h>`/`<Mod1-j>`/
`<Mod1-k>`/`<Mod1-l>` focus the nearest pane by direction — Neovim's own
built-in `<C-w>h/j/k/l` first (already "smart": nearest by screen
position, not just tree-adjacent), falling back to the nearest
focusable *floating* window in that direction (e.g. `mep.activitybar`'s
bar/panels, `mep.git.sidebar.toggle_dock()`'s own panel) when there's no
further normal-window neighbor that way — confirmed empirically while
building this: Neovim's own directional `wincmd` never enters a
floating window at all, and isn't even reliably directional *leaving*
one (it jumps back to some previous normal window regardless of which
direction was asked for) — so from inside a float, `focus` skips
`wincmd` entirely and looks for the nearest window (float or normal) in
that direction instead, letting `<Mod1-l>`/`<Mod1-h>` step through a stack of
several floats (a bar plus an open panel, say) one at a time rather than
bouncing straight back out. `<Mod1-S-h/j/k/l>` resize the current pane that
way (`h`/`k` shrink, `j`/`l` grow — Neovim's own `:resize`/`:vertical
resize`); `<Mod1-C-h/j/k/l>` move the pane's active tab into the
neighboring pane in that direction, focus following. `<Mod1-d>` removes
the active tab from the current pane (never deletes the buffer) — if
that was its last tab, the pane closes, unless it's the tabpage's only
remaining window, which falls back to the empty placeholder instead
(Neovim never allows closing the last window).

```lua
require('mep.window').setup({}) -- manual.enable=true, resize_step=3, auto.mfact=0.55, auto.nmaster=1
```

**Automatic layouts**: `master_left`/`master_right`/`master_top`/
`master_bottom` (a master area — `nmaster` buffers, `mfact` of the
space — against that edge, the rest stacked in the remainder),
`vertical`/`horizontal` (N equal columns/rows), `square` (a grid,
`ceil(sqrt(n))` columns), and `spiral` (each buffer after the first
halves whatever area remains, alternating axis — areas shrink
geometrically, unlike every other layout here). Applying one rebuilds
the tabpage's own real (non-floating — a `mep.git`/`mep.activitybar`
panel open alongside is left alone) windows into that shape once; it is
*not* a persistent mode — `:vsplit`/`:split`/`:close` behave normally
both before and after, nothing here keeps re-tiling on every window
event the way a real tiling WM would (Neovim splits are used for far
more than "tile my buffers": diffs, LSP peeks, quickfix, help,
terminals — auto-retiling on every one of those would fight all of
them). No default keymaps (there's no "correct" chord for eight
different layouts) — reachable as `:MepWindowLayout {name}` (tab-
completes) or `require('mep.window').auto.apply(name)`; populate
`auto.keymaps.<name>` yourself for whichever you actually want bound:

```lua
require('mep.window').setup({ auto = { keymaps = { square = { '<leader>wq' } } } })
```

**Scope notes**: the manual layout's tab bar is visible-only, not
clickable (`mep.git.sidebar`'s widgets are; a `winbar`'s own click
syntax has enough filename-escaping edge cases that it wasn't worth the
risk here) — use `<Mod1-n>`/`<Mod1-p>`. Automatic layouts don't nest inside
manual panes or vice versa — pick one mode for a given moment, not a
combination. Applying an automatic layout turns off `'equalalways'`
globally for the rest of the session (confirmed empirically: Neovim
re-equalizes every window the instant that option is switched back on,
which would otherwise immediately flatten the very layout just built,
and the same on every future incidental `:split`/`:close`) — run `:set
equalalways` yourself to opt back into Neovim's own default behavior.

### `mep.theme` — a curated colorscheme collection, with a fuzzy picker

28 built-in themes (`mep.theme.palettes`; 19 dark, 9 light) covering
most of the popular ones: `gruvbox-dark`/`-light`, `nord`/`-light`,
`dracula`, `tokyo-night`, `catppuccin-mocha`/`-latte`, `one-dark`/
`-light`, `everforest-dark`/`-light`, `rose-pine`/`-dawn`, `solarized-
dark`/`-light`, `monokai`, `kanagawa`, `ayu-dark`/`-mirage`, `github-dark`/
`-light`, `nightfox`, `horizon`, `zenburn`, `synthwave84`, `oxocarbon-dark`/
`-light`. Every theme is a single, compact ~13-field palette (a
background/foreground pair plus seven accent hues, `bg`/`fg`/`red`/
`green`/`yellow`/`blue`/`purple`/`cyan`/`orange`/`border`, a handful more
falling back sensibly if omitted) rendered by one shared, data-driven
generator (`mep.theme.engine`) covering every standard Neovim highlight
group plus common treesitter `@`-captures — not a hundred-group
hand-tuned theme apiece. The same "small palette drives everything" idea
`~/projects/mep-wm` (a separate window manager project, this
plugin's own real fg/bg/accent values cross-checked against its 15
built-in themes where the two overlap) uses for its own themes, just
with a few more hues than a WM needs for actual syntax highlighting.

```lua
require('mep.theme').setup({}) -- default='gruvbox-dark', apply_on_setup=true, keymaps.picker={'<leader>ut'}
require('mep.theme').apply('nord')
require('mep.theme').list() -- every registered theme name, sorted
require('mep.theme').register('my-theme', { dark = true, bg = '#000000', fg = '#ffffff', red = '#ff5555', green = '#50fa7b', yellow = '#f1fa8c', blue = '#8be9fd', purple = '#bd93f9', cyan = '#8be9fd', orange = '#ffb86c', border = '#44475a' })
```

`<leader>ut` (or `:MepThemePicker`) opens a fuzzy picker over every
registered theme — mep-wm's own theme-picker UX: moving the selection
applies the highlighted theme live, to the whole editor, *and* renders
a `mep.theme.swatch` color breakdown into the picker's own preview
sidebar (one line per palette field — a solid block of that color, its
name, and its hex value — so you can compare bg/fg/accent hues
side-by-side without hunting for something in your own buffers colored
by each one); Enter commits; Escape/`<C-c>` (or any other way of
closing without picking) reverts to whatever was active before you
opened it. `:MepTheme {name}` (tab-completes) applies one directly, no
picker. mep's own custom highlight groups (`MepGitAdd`, `MepSidebarTitle`,
`MepWindowTab`, ...) all `link` to standard groups this renders, so
they track whichever theme's active automatically — no extra work
needed per-library, but see `mep.theme.engine.apply`'s own header
comment for exactly how that re-link is triggered (a real `ColorScheme`
autocmd event, fired by hand — `nvim_set_hl` doesn't trigger one on its
own the way the `:colorscheme` command does).

**Scope notes**: applying a theme is a real, global, permanent editor
mutation (`highlight clear` + redefining every group) the same as a
real user's own `:colorscheme` — there's no "soft" preview that leaves
everything else untouched; the picker's revert-on-close is a second
full `apply()` back to the previous theme, not a true undo. No
plugin-specific highlight groups beyond mep's own (this project has no
runtime dependencies to color for) — if you use a plugin outside mep
alongside these themes, its own highlight groups won't be covered.

### `mep.chrome` — statusline/winbar/tabline/statuscolumn widgets, and an active-window border

One shared "widget" shape drives four independently opt-in targets —
`{ enable = false }` by default for `winbar`/`statuscolumn`, so those
change nothing until you configure them. `statusline`/`tabline` are the
two exceptions, on by default:

- `statusline`: a single widget that draws a plain full-width
  horizontal line (no text), so out of the box you get a blank
  separator instead of Neovim's own text-bearing default statusline
  (filename, modified flag, ruler position, ...).
- `tabline`: `widgets_before` defaults to a mode indicator
  (`mep.chrome.mode.name()` — "Normal"/"Insert"/"Visual"/"Terminal"/
  "Normal (Terminal)"/...), then one clickable circle per tabpage
  (`●` filled = current, `○` hollow = not — click one to switch to
  it), then `widgets_after` defaults to `+`/`x` to open a new tab /
  close the current one (`x` is a harmless no-op on the last tab —
  Neovim never allows closing the very last one).

Configuring `statusline.widgets`/`tabline.widgets_before`/
`tabline.widgets_after` yourself replaces those defaults entirely (the
circles themselves aren't a widget you configure away, only bookend —
same as the tab list used to be before this default existed):

```lua
require('mep.chrome').setup({
  statusline = {
    enable = true,
    widgets = {
      { text = function(ctx) return vim.api.nvim_buf_get_name(ctx.bufnr) end, hl = 'Directory' },
      '%=', -- a literal statusline alignment separator, same as `:help 'statusline'`
      {
        text = function(ctx) return ctx.active and '●' or '○' end,
        hl = function(ctx) return ctx.active and 'DiagnosticOk' or 'Comment' end,
        on_click = function(ctx) vim.notify('clicked window ' .. ctx.win) end,
        on_hover = function() require('mep.chrome.hover').show_tooltip('active/inactive indicator') end,
        on_leave = function() require('mep.chrome.hover').hide_tooltip() end,
      },
    },
  },
  winbar = { enable = true, widgets = { { text = 'WB' } } },
  tabline = { enable = true, widgets_before = {}, widgets_after = {} }, -- just the plain circles, no mode/+/x
  statuscolumn = { enable = true }, -- signs=true, numbers=true, folds=true, plus your own widgets
})
```

A widget is `{ text, hl, on_click, on_hover, on_leave }` — `text`/`hl`
can be plain values or `function(ctx)`, re-evaluated on every redraw;
`ctx` is `{ win, bufnr, active }` (the window the bar is being drawn
for — for `on_click`/`on_hover`/`on_leave`, the window actually under
the mouse). `statusline`/`winbar`/`tabline` share one renderer
(`mep.chrome.render`) and are each wired up as a single, global
`%{%...%}` funcref; `statusline`/`winbar` re-evaluate per window via
Neovim's own `g:statusline_winid` (`:help 'statusline'`), while
`tabline` (like Neovim's own `'tabline'` option) is a single global bar
re-evaluated for whichever window is current — not something this
library loops over windows to set either way. `statuscolumn`
re-evaluates per screen *line* (`v:lnum`/`v:relnum`/`v:virtnum`), with
`%s`/`%C` (sign/fold columns) passed through when `signs`/`folds` are
enabled.

Hover (`on_hover`/`on_leave`, `mousemoveevent`-driven — real per-move
overhead, only turned on when `statusline` or `winbar` is actually
enabled) tracks each widget's on-screen column range as it's rendered;
that tracking is only reliable up to and including the *first* `'%='`
in a widget list — a second one still renders fine, its widgets just
won't get hover callbacks. `require('mep.chrome.hover').show_tooltip(text)`
/ `.hide_tooltip()` are a small floating-window helper for exactly the
"pop up a tooltip on hover" case; changing a widget's own look on hover
is just `on_hover`/`on_leave` toggling some state its own `text`/`hl`
function reads.

```lua
require('mep.chrome').setup({ border = { enable = true } }) -- the default
```

The active window's border (magenta by default, `MepChromeBorderActive`)
is native, not a floating overlay — `winhighlight` remaps on the real
window options (`WinSeparator` for left/right, `WinBar`/`StatusLine`
for top/bottom), so it stays fully compatible with a real,
content-bearing statusline/winbar (this library's own, or none at all).
It's on by default and useful even with every other `mep.chrome` target
left off — it just recolors whatever separators/statusline Neovim (or
your own config) is already drawing. Per `:help winhighlight`, a
vertical separator's highlight is owned by the window to *its* left,
so the left edge recolors your left neighbor, not you — a window at
the screen edge simply has no separator there to color, the same
inherent limit any terminal-based split layout has.

### `mep.ai` — gptel-style LLM streaming and a tool-calling agent, in any buffer

`:MepAiSend` (`gl` in normal mode) sends the *whole current buffer's*
text to a configured LLM and streams the response in directly at the
cursor as it arrives — the same live "watch it type into the buffer"
UX real Emacs gptel has, not a separate chat window. `:MepAiCancel`
(`<leader>ax`) stops an in-flight request early; whatever already
streamed in stays. Works in any buffer — no filetype/language
restriction.

`gl`/`gk` in **visual** mode are a different flow entirely: a genuinely
interactive, multi-turn, tool-calling agent (`mep.ai.agent`) that opens
a persistent side panel to converse in, scoped to the selection as its
editable target but still given the whole buffer as context (see
"Tool-calling agent (visual-mode `gl`/`gk`)" below for the full
picture). `gl` gives it nothing beyond the block's own content (which
may itself carry instructions, e.g. a `TODO` comment) and its own
judgment; `gk` first opens a small floating-window prompt for an
explicit instruction to send alongside the block — both are real,
independent ways to direct it, exactly the way normal-mode `gl` above
takes no prompt and `gk` did before. `:MepAiAgent`/`:MepAiAgentPrompt`
are the same two flows as range-aware commands
(`:'<,'>MepAiAgent` works directly from Visual mode's own command line
too).

`mep.ai.send_selection()` (`:MepAiSendSelection`/
`:MepAiSendSelectionPrompt`, both range-aware, no keymap bound to
either anymore) is the *older*, single-shot version of a
selection-scoped edit: no tools, no panel, no back-and-forth — it's
told, in a dedicated system prompt (`agent_system_prompt`, distinct
from the plain `system_prompt` `mep.ai.send()` uses), to respond with
*only* the block's replacement text (no explanation, no markdown code
fences), and that response streams in *replacing* the selection
directly. Kept as a lower-level API for when a plain one-shot block
rewrite, with none of the tool-calling agent's overhead, is genuinely
all that's wanted.

Genuinely asynchronous, not just "doesn't freeze the editor": you're
free to switch buffers/windows, keep editing the buffer a `mep.ai.send`/
`send_selection` response is streaming into, or move the cursor away
entirely while it streams. The landing spot is tracked with a real
extmark, not a frozen `{row, col}`, so it stays correct even if
something else edits the buffer above it in the meantime; the cursor
auto-follows the streamed text landing (the live "watch it type"
effect) only for as long as it's still sitting exactly where the last
chunk left it — move it yourself and this stops dragging it back, so
navigating away never fights you.

```lua
require('mep.ai').setup({}) -- default provider: {'openai', 'anthropic', 'ollama'}
```

"Connect to an LLM" means picking one of three named `providers`
presets, or adding your own alongside them (`setup()` deep-merges onto
each preset, so overriding one field — `model` — doesn't require
repeating the rest):

- **`openai`** — the Chat Completions API, `api_key_env =
  'OPENAI_API_KEY'`, `model = 'gpt-4o-mini'` unless overridden.
- **`anthropic`** — the Messages API, `api_key_env =
  'ANTHROPIC_API_KEY'`, `max_tokens = 4096` and `model =
  'claude-sonnet-5'` unless overridden.
- **`ollama`** — a local `ollama serve`, no API key at all, talking to
  its own OpenAI-*compatible* `/v1/chat/completions` endpoint (so it
  needs no separate request/response handling of its own — see below).
  `model = 'llama3.2'` unless overridden, since this preset's whole
  point is working immediately once `ollama serve` is running and that
  model's been pulled.

`provider` (default `{'openai', 'anthropic', 'ollama'}`, in exactly
that priority order) can be either a single name — always use exactly
that one, prompting interactively for its key if it needs one it
doesn't already have — or a *list*, tried in order with **no prompting
at all**: each entry is silently skipped unless it already has a
`model` configured and (if it needs a key) that key is already sitting
in its own `api_key_env`. The shipped default list is exactly this
"don't make me type a key in" flow — set `OPENAI_API_KEY`/
`ANTHROPIC_API_KEY` in your shell profile (or wherever you already keep
secrets — `mep.ai` never reads anything but the environment variable
name itself) and whichever one is set gets used automatically; with
neither set, it lands on the local `ollama` preset, which needs no key
at all — so `:MepAiSend` (`gl`) already works the moment `ollama serve`
is running, with zero `setup()` calls beyond the plugin being loaded.

Only two request/response *shapes* exist under the hood
(`mep.ai.providers`) — `kind = 'openai'` and `kind = 'anthropic'` —
covering every preset above (Ollama's own compatible endpoint reuses
the `openai` shape) plus any other OpenAI-compatible service (Groq,
OpenRouter, DeepSeek, ...) you point a custom preset's `endpoint` at.

For a single, explicitly-named provider (not a fallback list), an API
key is resolved once per session, the first time it's actually needed:
a literal `providers.<name>.api_key`, then that provider's own
`api_key_env` environment variable, then (if neither) an interactive
`vim.fn.inputsecret()` prompt — cached in memory only for the rest of
the session, never written to disk. `:MepAiSetKey [provider]`
(tab-completes provider names) prompts ahead of time instead of waiting
for the first `:MepAiSend` — `[provider]` is required (not inferred)
when `provider` is a fallback list, since it'd otherwise be ambiguous
which one you meant. A provider with no `api_key_env` at all (the local
`ollama` preset) is never prompted, list or not.

Streaming is a real `curl` subprocess (`mep.ai.job`, via `mep.core.job`
— the same job-runner `mep.org.babel`/`mep.picker` already use) reading
Server-Sent Events line by line, not an HTTP client Lua dependency —
`curl` is an external tool here, the same class of dependency `git`/a C
compiler already are for `mep.treesitter`. The request body is written
to a real temp file and passed as `curl --data-binary @<path>` (the
same "temp file, not process stdin" idiom `mep.org.babel`'s own
compiled-language execution uses), and `--fail-with-body` makes curl's
own exit code reflect the HTTP status while still printing the error
body, so an auth failure or bad model name surfaces as a real,
readable error instead of a silent empty stream. Only one request
streams at a time — `:MepAiSend` while another is still in flight
refuses instead of racing two responses into the same buffer position.

```lua
require('mep.ai').setup({}) -- keymaps: send/agent={'gl'}, agent_prompt={'gk'}, cancel={'<leader>ax'}; provider={'openai','anthropic','ollama'}
require('mep.ai').setup({ provider = 'anthropic' }) -- always this one, prompting for a key if ANTHROPIC_API_KEY isn't set
require('mep.ai').setup({ provider = { 'anthropic', 'ollama' } }) -- your own, shorter fallback list
require('mep.ai').setup({ system_prompt = 'Answer tersely.' }) -- prepended as a system message, unset by default
require('mep.ai').setup({ tools = { 'read_file', 'list_dir' } }) -- drop run_command from the agent's tool set entirely
```

**Trying it locally, no account needed**: this repo's own `flake.nix`
devShell lists `pkgs.ollama` (plus `pkgs.curl`, in case it isn't
already on `PATH`) for exactly this. In one terminal:

```sh
nix develop
ollama serve
```

and in another (same `nix develop` shell):

```sh
ollama pull llama3.2
```

then `:MepAiSend` (`gl`) already talks to it at its default
`http://localhost:11434` — no `setup()` call needed at all beyond
whatever loads the plugin, since `ollama` is the last, always-reachable
entry in the default fallback list. The same `ollama`/`llama3.2` setup
also drives the tool-calling agent below — pull a plain `llama3.2` (not
the smaller `:1b` tag), which is the one confirmed to actually emit
real `tool_calls` rather than hallucinating JSON as plain text.

**Scope note** (`mep.ai.send`/`send_selection` only, the plain
streaming flows): sends the buffer's/selection's text as a `user`
message and streams one response back — no multi-turn conversation
history, no tool-calling. See below for the flow that has both.

#### Tool-calling agent (visual-mode `gl`/`gk`)

`mep.ai.agent.start()` — what visual-mode `gl`/`gk` actually trigger —
is a real, interactive, multi-turn session: it opens `mep.ai.panel` (a
persistent side panel, `mep.sidebar`-based, the same building block
`mep.git`'s own status panel and `mep.activitybar`'s flyouts use) and
converses there, sending the *whole current buffer* as context on every
call (plus, for a visual-mode call, the selection specifically as its
editable target) — the model can ask to run a **tool** at any point,
which pauses for an explicit permission decision before anything
actually happens.

Three tools ship by default (`config.tools`, trim the list to change
what's on offer):

- **`read_file`** — read a text file by path. `risk = 'read'`.
- **`list_dir`** — list a directory's entries. `risk = 'read'`.
- **`run_command`** — run a shell command (`sh -c`) from Neovim's
  current working directory, returning exit code/stdout/stderr.
  `risk = 'exec'`.

Every tool call shows up in the panel as a permission prompt before it
runs — `a` allows it once, `d` denies it, and `A` grants a *standing*
"always allow this session" approval, but **only** for `risk = 'read'`
tools: `run_command` never gets a blanket approval, no matter what's
already been granted for the read-only tools — real shell execution
always asks, every single time. Press `i` in the panel to type a
free-text reply at any point the agent isn't mid-turn or waiting on a
permission decision — answering a clarifying question it asked, giving
it a further instruction, anything a real back-and-forth needs.
`:MepAiCancel`/`<leader>ax` stops the agent's *current* turn (the
session itself, and its transcript, stay open); starting a new agent
session cancels whatever the previous one still had in flight.

There is deliberately no dedicated "edit the buffer" tool — an edit
happens the same way a human collaborator editing over your shoulder
would do it: the agent runs a real shell command against the file on
disk (permission-gated exactly like any other `run_command` call), and
Neovim's own `:checktime` semantics pick the change back up into the
live buffer afterward (if the buffer has no unsaved local edits — if it
does, this warns instead of clobbering them, same as running
`:checktime` by hand always has).

Tool-calling requests are deliberately **non-streaming**
(`mep.ai.job.request`, alongside the streaming `mep.ai.job.start` the
plain flows use) — a tool call's own arguments arrive fragmented across
many small deltas in both provider shapes, and a turn that calls tools
has to finish completely before anything (which tools to run) can
happen anyway, so streaming buys nothing there.

## Requirements

- Neovim >= 0.9.
- `rg` (ripgrep) on `PATH` for `:MepLiveGrep`. `:MepFindFiles` uses `rg`
  too when present (faster, respects `.gitignore`) and otherwise falls
  back to a synchronous directory walk.
- `git` and a C compiler (`cc`/`gcc`/`clang`) on `PATH` for
  `mep.treesitter`'s parser installer. Not required for treesitter
  *activation*, which only uses parsers already available.

## Setup

`require('mep').setup(opts)` is optional — every library works with its
own defaults if you never call it — but it's how you configure more than
one library at once: `opts.<name>` is forwarded to `mep.<name>.setup()`.

```lua
require('mep').setup({
  theme = { default = 'nord' },                 -- mep.theme.config.defaults
  sanity = { leader = ' ' },                    -- mep.sanity.config.defaults
  dashboard = { auto_open = true },             -- mep.dashboard.config.defaults
  icons = { style = 'nerd_font' },              -- mep.icons.config.defaults
  filetree = { width = 30 },                    -- mep.filetree.config.defaults
  treesitter = { fold = true },                 -- mep.treesitter.config.defaults
  org = { todo_keywords = { 'TODO', 'DOING', 'DONE' } }, -- mep.org.config.defaults
  markdown = { tables = true, code_blocks = true }, -- mep.markdown.config.defaults
  picker = { debounce_ms = { dynamic = 150 } }, -- mep.picker.config.defaults
  whichkey = { triggers = { '<leader>' } },     -- mep.whichkey.config.defaults
  sidebar = { position = 'right' },             -- mep.sidebar.config.defaults
  notify = { position = 'top-right' },          -- mep.notify.config.defaults
  activitybar = { position = 'right' },         -- mep.activitybar.config.defaults
  lsp = { enable = true },                      -- mep.lsp.config.defaults
  completion = { sources = { 'lsp', 'buffer', 'path' } }, -- mep.completion.config.defaults
  url = { keymaps = { open = { 'gx' } } },      -- mep.url.config.defaults
  git = { sidebar = { position = 'left' } },    -- mep.git.config.defaults
  window = { manual = { resize_step = 5 } },    -- mep.window.config.defaults
  project = { readme_names = { 'readme.txt' } }, -- mep.project.config.defaults
  scratch = { filetype = 'markdown' },          -- mep.scratch.config.defaults
})
```

Equivalent to calling `require('mep.sanity').setup({ leader = ' ' })`,
`require('mep.icons').setup({ style = 'nerd_font' })`, and so on yourself —
use whichever fits how you organize your config. Omit a library's key (or
the whole call) to just get its defaults.

### Global modifier keys

Default keymaps across mep are written with a `<Mod1-...>` placeholder
instead of hard-coding `<A-...>`: `Mod1` resolves to Alt (`'A'`) on
Linux/Windows and Option (`'M'`, i.e. Option-as-Meta) on macOS, and every
library's `setup()` expands the placeholder (via `mep.core.keys`) in both
its defaults and any keymaps you pass in, so you can use `<Mod1-...>` in
your own overrides too. Neovim itself treats `<A-...>` and `<M-...>` as
the same modifier, so the per-platform default is about intent — the part
that matters is that you can retarget it *once, globally*:

```lua
require('mep').setup({
  -- Use Cmd instead of Option for every Mod1 binding (macOS GUIs like
  -- Neovide; terminals generally can't send Cmd):
  mods = { mod1 = 'D' },
  ...
})
```

Additional names (`mod2`, `mod3`, ...) have no built-in default but expand
the same way once configured (e.g. `mods = { mod2 = 'C' }` makes
`<Mod2-x>` mean `<C-x>`).

Note for macOS terminal users: for Option to reach Neovim as Alt/Meta at
all, the terminal must be set to send it that way — iTerm2's "Option key:
Esc+", kitty's `macos_option_as_alt`, Neovide's
`macos_option_key_is_meta`. That's a terminal setting, not something a
plugin can do for you.

Suggested keymaps (not set automatically — this plugin doesn't touch your
keymaps for you):

```lua
vim.keymap.set('n', '<leader>ff', '<cmd>MepFileTreeToggle<cr>')
vim.keymap.set('n', '<leader>pf', '<cmd>MepFindFiles<cr>')
vim.keymap.set('n', '<leader>bb', '<cmd>MepBuffers<cr>')
vim.keymap.set('n', '<leader>bs', '<cmd>MepScratch<cr>')
vim.keymap.set('n', '<leader>fg', '<cmd>MepLiveGrep<cr>')
vim.keymap.set('n', '<leader>fb', '<cmd>MepBufferSearch<cr>')
vim.keymap.set('n', '<leader>po', '<cmd>MepProjects<cr>')
vim.keymap.set('n', '<leader>pr', '<cmd>MepProjectSearch<cr>')
```

## Building your own picker

`mep.picker.Picker` is the general engine; a "source" is just a table of
opts describing where items come from. See
`lua/mep/picker/sources/buffer_lines.lua` for the simplest example (a
static list, fuzzy-filtered client-side) and `sources/grep.lua` for a
dynamic one (the source does its own searching per keystroke via an async
job):

```lua
require('mep.picker').start({
  prompt_title = 'My Picker',
  items = { { name = 'foo' }, { name = 'bar' } }, -- or `get_items = function(query, cb) ... end`
  entry_to_string = function(item) return item.name end,
  preview = function(item, preview_buf, preview_win) ... end,
  on_select = function(item) ... end,
})
```

## Development

- `just try` (or `nix run`, from outside a dev shell) — opens a scratch
  Neovim with this checkout loaded and `setup({})` applied, isolated from
  your real config; this is also what shows off `mep.dashboard` in
  practice, since `setup({})` enables its default auto-open. See
  `scripts/try_init.lua`.
- `just test` — runs the busted unit test suite (needs a `nix develop`
  shell, via `.envrc`/direnv or manually). See `spec/README.md` for how
  it's wired up (busted-via-nlua) and its one real constraint (no real
  subprocesses inside a spec).

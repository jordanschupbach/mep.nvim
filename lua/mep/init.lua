--- mep.nvim: a zero-dependency, mini.nvim-style collection of Neovim
--- libraries. `require('mep')` gives you `setup()` plus direct access to
--- each library (`mep.core`, `mep.sanity`, `mep.dashboard`, `mep.icons`,
--- `mep.filetree`, `mep.treesitter`, `mep.org`, `mep.markdown`, `mep.picker`,
--- `mep.whichkey`, `mep.sidebar`, `mep.notify`, `mep.activitybar`,
--- `mep.lsp`, `mep.diagnostics`, `mep.completion`, `mep.url`, `mep.git`, `mep.window`,
--- `mep.theme`, `mep.chrome`, `mep.project`, `mep.ai`, `mep.scratch`,
--- `mep.symbols`, `mep.hints`, `mep.dap`, `mep.docs`, `mep.flashcards`,
--- `mep.help`, `mep.colorizer`, `mep.leetcode`, `mep.roam`, `mep.run`,
--- `mep.repl`, `mep.snippet`, `mep.todoscan`, `mep.zen`, `mep.clipboard`,
--- `mep.bib`, `mep.todo`);
--- libraries can equally be required and configured directly, e.g.
--- `require('mep.picker').setup({ ... })`.
local M = {}

-- Libraries that take their own opts table via setup(opts) and are
-- reachable as `opts.<name>` from the top-level setup() call.
-- `whichkey` is deliberately after `sanity`: if `<leader>` is one of its
-- triggers (the default), its own keymap needs `vim.g.mapleader` already
-- set by `sanity`'s own setup() — Neovim resolves `<leader>` in a
-- keymap's lhs to the *current* mapleader at the point the mapping is
-- defined, not when it's later pressed, so whichkey.setup() has to run
-- after sanity.setup() actually applies that option. `notify` is listed
-- after `sidebar` for the same "reads the other library's options"
-- reasoning (its own history panel is a `mep.sidebar.new(...)`
-- instance) and *before* `activitybar`, since `activitybar.setup()`
-- calls `mep.notify.install()` to hook `vim.notify` (its own
-- notifications panel is just a view onto `mep.notify`'s entries now,
-- not a separate hook of its own); it also needs to be after `sanity`
-- for the same `<leader>`-resolved-at-definition-time reason as
-- `whichkey` above — `notify.setup()` binds `keymaps.toggle` (default
-- `<leader>nn`) globally. `activitybar` is
-- listed after `sidebar` for the same "reads the other library's
-- options" reasoning, though less strictly load-bearing: every
-- `mep.sidebar.new(...)` call it makes fully specifies its own
-- position/width/animate, so only the sidebar-global fallbacks it
-- *doesn't* override (keymaps, resize/animation timing) would be
-- affected by ordering here at all. `lsp`/`completion` have no ordering
-- dependency on anything else here (see `completion`'s own note about
-- `lsp.completion = false` below — that's a *config value* coordination,
-- not a load-order one); they're last simply because they were added
-- last. `url` has no ordering dependency on anything here either — it's
-- last for the same "added last" reason. `git` is listed after `sidebar`
-- for the same non-strictly-load-bearing reason as `activitybar` (`mep.
-- git.sidebar` builds its own `mep.sidebar.new(...)` calls fully
-- specified too) — otherwise last-added, no real ordering dependency.
-- `window` has no ordering dependency on anything here either — last
-- because it was added last. `chrome` has no ordering dependency
-- either — its widgets are opt-in and read config at render time, not
-- setup time, so it's simply added at the end. `project` has no
-- ordering dependency either — it only ever touches `mep.picker` at
-- `M.picker()` call time (via `require`), never at `setup()` time, so
-- it's simply added at the end too. `ai` has no ordering dependency
-- either — it only ever touches the network from `M.send()`/`M.
-- set_key()`, both explicit user actions, never at `setup()` time
-- (whose only side effect is binding its own keymaps), so it's simply
-- added last. `scratch` has no ordering dependency either — `open()`
-- creates its buffer lazily on first call, not at `setup()` time, so
-- it's simply added at the end too. `symbols` has no ordering
-- dependency either — its own `setup()` only ever binds its own
-- trigger keymap and reads its own config at `open()` time, so it's
-- simply added at the end too. `hints` has no ordering dependency
-- either — its own `setup()` only ever binds its own trigger keymaps
-- and reads its own config at trigger time, so it's simply added at
-- the end too. `dap` has no ordering dependency either — its own
-- `setup()` only ever binds its own global keymaps and reads its own
-- config at session-start time, so it's simply added at the end too.
-- `docs` has no ordering dependency either — its own `setup()` only
-- ever binds its own global keymaps and reads its own config at press
-- time, so it's simply added at the end too. `flashcards` has no
-- ordering dependency either — it reads `mep.org.property`/`tags`/
-- `outline`/`headline`/`plan`/`agenda` directly wherever it needs them
-- (pure parsing functions, not gated on `mep.org.setup()` having run),
-- and its own `setup()` only binds its own global keymap, so it's
-- simply added at the end too. `help` has no ordering dependency
-- either — it reads `mep.picker`/`mep.whichkey` directly wherever it
-- needs them (only at picker-open time, not `setup()` time), so it's
-- simply added at the end too. `colorizer` has no ordering dependency
-- either — its own `enable()` (called from `setup()`) only attaches to
-- already-loaded buffers and future ones via its own global augroup, no
-- dependency on any other library's setup having run first, so it's
-- simply added at the end too. `leetcode` has no ordering dependency
-- either — it reads `mep.org.babel`/`mep.picker`/`mep.core` directly
-- wherever it needs them (only at run-tests/fetch/submit/picker-open
-- time, not `setup()` time), so it's simply added at the end too.
-- `roam` has no ordering dependency either — it reads `mep.org.id`/
-- `link`/`headline`/`outline`/`capture`/`mep.picker`/`mep.sidebar`
-- directly wherever it needs them (only at picker-open/panel-open/
-- daily-note/new-note time, not `setup()` time), so it's simply added
-- at the end too. `run` has no ordering dependency either — it reads
-- `mep.org.babel` directly wherever it needs it (only at run-current-
-- file time, not `setup()` time), so it's simply added at the end too.
-- `repl` has no ordering dependency either — its own `setup()` only
-- binds its own keymaps and a `TermOpen` autocmd, no dependency on any
-- other library's setup having run first, so it's simply added at the
-- end too. `snippet` has no ordering dependency either — its own
-- `setup()` only binds its own `<Tab>`/`<S-Tab>` keymaps, and `mep.
-- completion`'s own soft dependency on it (its `snippet` source, and
-- the snippet-shaped-`insertText` branch of its `lsp` source) is
-- resolved lazily via `require` at completion time, not `setup()`
-- time, so it's simply added at the end too. `todoscan` has no ordering
-- dependency either — its own `setup()` only ever attaches its live
-- highlighting to already-loaded buffers and future ones via its own
-- global augroup, no dependency on any other library's setup having run
-- first, so it's simply added at the end too. `zen` has no ordering
-- dependency either — its own `setup()` only ever stores config, doing
-- nothing at all until `toggle()`/`enable()` is actually called (each
-- of `mep.activitybar`/`mep.filetree`/`mep.symbols`/`mep.chrome` is
-- `require`d lazily then, softly — not depended on at `setup()` time),
-- so it's simply added at the end too. `clipboard` has no ordering
-- dependency either — its own `setup()` only ever sets `'clipboard'`/
-- `vim.g.clipboard`, both plain option/global writes with no
-- dependency on any other library's setup having run first, so it's
-- simply added at the end too. `bib` has no ordering dependency either
-- — it reads `.bib` files and binds its own keymap only at `setup()`/
-- picker-open time, no dependency on any other library's setup having
-- run first (its `<localleader>ir` default only resolves usefully once
-- `vim.g.maplocalleader` is set, but that's a user prerequisite, not
-- an ordering dependency on another library in this list — see `mep.
-- bib.bib`'s own header comment), so it's simply added at the end too.
-- `todo` has no ordering dependency on anything else in this list
-- either — it reads `mep.org.agenda`/`mep.sidebar` directly, only at
-- panel-open time, not `setup()` time; its own `setup()` does bind a
-- global `<leader>`-based keymap (`keymaps.toggle`), the same
-- `<leader>`-resolved-at-definition-time constraint `whichkey`/`theme`/
-- `notify` above are about, but since `sanity` is already first in this
-- list, appending `todo` at the end trivially satisfies that too —
-- simply added at the end.
-- `theme` is listed right
-- after `sanity`,
-- deliberately, for two reasons that both point the same direction:
-- its own setup() (which applies a colorscheme by default,
-- `apply_on_setup`) should establish the color scheme before anything
-- else in this list renders, the same reasoning a real init.lua would
-- have for sourcing `colorscheme` early — *but* it also binds its own
-- `<leader>`-based keymap (`keymaps.picker`), which needs `sanity`'s
-- own setup() to have already applied `vim.g.mapleader` first, the same
-- `<leader>`-resolved-at-definition-time constraint `whichkey`'s own
-- ordering note above is about (confirmed the hard way: `theme` listed
-- *before* `sanity` bound `<leader>ut` against the wrong, default
-- mapleader).
local CONFIGURABLE_LIBRARIES = {
  'sanity',
  'theme',
  'dashboard',
  'icons',
  'filetree',
  'treesitter',
  'org',
  'markdown',
  'picker',
  'whichkey',
  'sidebar',
  'notify',
  'activitybar',
  'lsp',
  -- Listed right after `lsp`, deliberately (a real ordering
  -- dependency, unlike most of this list): `mep.diagnostics.setup()`
  -- forces `vim.diagnostic.config({ virtual_text = false })` so its own
  -- circles fully replace native virtual text — `mep.lsp.setup()` also
  -- calls `vim.diagnostic.config(options.diagnostics)` (its own
  -- `virtual_text = true` default), so `diagnostics` has to run after
  -- `lsp` for its override to be the one that sticks.
  'diagnostics',
  'completion',
  'url',
  'git',
  'window',
  'chrome',
  'project',
  'ai',
  'scratch',
  'symbols',
  'hints',
  'dap',
  'docs',
  'flashcards',
  'help',
  'colorizer',
  'leetcode',
  'roam',
  'run',
  'repl',
  'snippet',
  'todoscan',
  'zen',
  'clipboard',
  'bib',
  'todo',
}

--- opts: `{ theme = {...}, sanity = {...}, dashboard = {...}, icons =
--- {...}, filetree = {...}, treesitter = {...}, org = {...}, markdown =
--- {...}, picker =
--- {...}, whichkey = {...}, sidebar = {...}, notify = {...}, activitybar
--- = {...}, lsp =
--- {...}, diagnostics = {...}, completion = {...}, url = {...}, git = {...}, window = {...},
--- chrome = {...}, project = {...}, ai = {...}, scratch = {...}, symbols
--- = {...}, hints = {...}, dap = {...}, docs = {...}, flashcards =
--- {...}, help = {...}, colorizer = {...}, leetcode = {...}, roam =
--- {...}, run = {...}, repl = {...}, snippet = {...}, todoscan = {...},
--- zen = {...}, clipboard = {...}, bib = {...}, todo = {...} }` (all optional). Each sub-table is
--- forwarded to that library's own `setup()`; see `mep.<name>.config.
--- defaults` for each library's shape. Note: mep.treesitter's default
--- `ensure_installed = true` means this can kick off background
--- network/compiler activity (cloning and building any curated parser
--- that isn't already available) — pass `treesitter = { ensure_installed
--- = false }` to opt out. mep.org's default `highlight = true` does the
--- same for the `org` parser alone, independent of that setting. mep.
--- markdown's own default `highlight = true` does the same for the
--- `markdown`/`markdown_inline` parsers. mep.lsp
--- needs Neovim >= 0.11 (`vim.lsp.config`/`vim.lsp.enable`, newer than
--- this project's own general >= 0.9 baseline) — on anything older it
--- warns and no-ops rather than erroring, same as every other library's
--- own graceful degradation when an optional capability isn't there. If
--- you use both `lsp` and `completion` together, pass `lsp = {
--- completion = false }` — otherwise mep.lsp's own native `vim.lsp.
--- completion.enable` hookup and mep.completion's `lsp` source end up
--- both triggering LSP completion independently. mep.url's own `gx`
--- overrides Neovim's own built-in default keymap of the same name
--- (Neovim >= 0.10) — an enhancement of it, not a conflict.
function M.setup(opts)
  opts = opts or {}
  require('mep.config').setup(opts)
  for _, name in ipairs(CONFIGURABLE_LIBRARIES) do
    require('mep.' .. name).setup(opts[name])
  end
end

local LAZY_LIBRARIES = {
  core = true,
  theme = true,
  sanity = true,
  dashboard = true,
  icons = true,
  filetree = true,
  treesitter = true,
  org = true,
  markdown = true,
  picker = true,
  whichkey = true,
  sidebar = true,
  notify = true,
  activitybar = true,
  lsp = true,
  diagnostics = true,
  completion = true,
  url = true,
  git = true,
  window = true,
  chrome = true,
  project = true,
  ai = true,
  scratch = true,
  symbols = true,
  hints = true,
  dap = true,
  docs = true,
  flashcards = true,
  help = true,
  colorizer = true,
  leetcode = true,
  roam = true,
  run = true,
  repl = true,
  snippet = true,
  todoscan = true,
  zen = true,
  clipboard = true,
  bib = true,
  todo = true,
  version = true,
}

setmetatable(M, {
  __index = function(t, key)
    if LAZY_LIBRARIES[key] then
      local mod = require('mep.' .. key)
      rawset(t, key, mod)
      return mod
    end
  end,
})

return M

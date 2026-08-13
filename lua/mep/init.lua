--- mep.nvim: a zero-dependency, mini.nvim-style collection of Neovim
--- libraries. `require('mep')` gives you `setup()` plus direct access to
--- each library (`mep.core`, `mep.sanity`, `mep.dashboard`, `mep.icons`,
--- `mep.filetree`, `mep.treesitter`, `mep.org`, `mep.markdown`, `mep.picker`,
--- `mep.whichkey`, `mep.sidebar`, `mep.activitybar`, `mep.lsp`,
--- `mep.completion`, `mep.url`, `mep.git`, `mep.window`, `mep.theme`,
--- `mep.chrome`, `mep.project`);
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
-- after sanity.setup() actually applies that option. `activitybar` is
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
-- it's simply added at the end too. `theme` is listed right
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
  'activitybar',
  'lsp',
  'completion',
  'url',
  'git',
  'window',
  'chrome',
  'project',
}

--- opts: `{ theme = {...}, sanity = {...}, dashboard = {...}, icons =
--- {...}, filetree = {...}, treesitter = {...}, org = {...}, markdown =
--- {...}, picker =
--- {...}, whichkey = {...}, sidebar = {...}, activitybar = {...}, lsp =
--- {...}, completion = {...}, url = {...}, git = {...}, window = {...},
--- chrome = {...}, project = {...} }` (all optional). Each sub-table is
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
  activitybar = true,
  lsp = true,
  completion = true,
  url = true,
  git = true,
  window = true,
  chrome = true,
  project = true,
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

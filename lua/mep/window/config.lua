local M = {}

M.defaults = {
  manual = {
    -- Bind the manual-layout keymaps automatically on setup().
    enable = true,
    -- How many columns/rows a single resize press moves the nearest
    -- split boundary.
    resize_step = 3,
    keymaps = {
      -- Split the current pane side by side (`:vsplit`) / stacked
      -- (`:split`), loading the shared "empty pane" scratch buffer into
      -- the new one and selecting it — mep-wm's own `Mod+v`/`Mod+s`.
      split_vertical = { '<Mod1-v>' },
      split_horizontal = { '<Mod1-s>' },
      -- Focus the nearest pane in a direction — Neovim's own built-in
      -- `<C-w>h/j/k/l` under the hood, already "smart" (screen-position
      -- based, not just tree-adjacent) — mep-wm's `Mod+h/j/k/l`.
      focus_left = { '<Mod1-h>' },
      focus_down = { '<Mod1-j>' },
      focus_up = { '<Mod1-k>' },
      focus_right = { '<Mod1-l>' },
      -- Resize the current pane in that direction — `l`/`j` grow it,
      -- `h`/`k` shrink it, except right at the pane's own right/bottom
      -- edge (no room to grow into), where the roles flip so `l`/`j`
      -- and `h`/`k` still do opposite things instead of both growing
      -- or both shrinking (see `mep.window.panes.resize`'s own header
      -- for exactly how) — mep-wm's `Mod+Shift+h/j/k/l`.
      resize_left = { '<Mod1-S-h>' },
      resize_down = { '<Mod1-S-j>' },
      resize_up = { '<Mod1-S-k>' },
      resize_right = { '<Mod1-S-l>' },
      -- Move the active tab out of the current pane and into the
      -- neighboring one in that direction (collapsing the current pane
      -- if that was its last tab), focus following it — mep-wm's own
      -- `Mod+Ctrl+h/j/k/l`.
      move_left = { '<Mod1-C-h>' },
      move_down = { '<Mod1-C-j>' },
      move_up = { '<Mod1-C-k>' },
      move_right = { '<Mod1-C-l>' },
      -- Cycle the active tab within the current pane — mep-wm's own
      -- `Mod+n`/`Mod+p` *and* `Mod+Tab`/`Mod+Shift+Tab`, both bound to
      -- the same two actions there too, not an either/or choice.
      next_tab = { '<Mod1-n>', '<Mod1-Tab>' },
      prev_tab = { '<Mod1-p>', '<Mod1-S-Tab>' },
      -- Remove the active tab from the current pane (never deletes the
      -- buffer itself) — if it was the pane's last tab, close the pane
      -- (or, if it's the tabpage's only remaining window, fall back to
      -- the shared empty-pane buffer instead, since the last window
      -- can't be closed).
      remove = { '<Mod1-d>' },
    },
  },
  auto = {
    -- On-demand only: applying one of these rebuilds the *current*
    -- tabpage's windows into that arrangement once — nothing here is
    -- continuously enforced the way a real window manager's tiling is
    -- (Neovim splits are used for far more than "tile my buffers":
    -- diffs, LSP peeks, quickfix, help, terminals — auto-retiling on
    -- every window event would fight all of those). `:vsplit`/`:split`
    -- behave normally the rest of the time.
    mfact = 0.55, -- master area's share of the split (0.1-0.9)
    nmaster = 1, -- how many windows sit in the master area
    -- Reachable as `:MepWindowLayout <name>` (`master_left`/
    -- `master_right`/`master_top`/`master_bottom`/`vertical`/
    -- `horizontal`/`square`/`spiral`) regardless; every list here is
    -- empty by default — unlike `manual`'s keymaps (an explicit ask,
    -- replicating specific muscle-memory bindings), these have no
    -- "correct" default chord and there are eight of them, so nothing's
    -- bound automatically. Populate whichever you want, e.g. `{
    -- master_left = { '<leader>wm' }, spiral = { '<leader>ws' } }`.
    keymaps = {
      master_left = {},
      master_right = {},
      master_top = {},
      master_bottom = {},
      vertical = {},
      horizontal = {},
      square = {},
      spiral = {},
    },
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied keymaps alike) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

local M = {}

M.defaults = {
  -- Which edge of the editor the sidebar opens against.
  -- 'left'/'right' are vertical splits sized by `width`; 'top'/'bottom'
  -- are horizontal splits sized by `height`.
  position = 'right',
  width = 30,
  height = 15,
  -- `false` (default): a real split — participates in normal window
  -- layout, reflows neighboring windows, the same persistent-panel
  -- approach `mep.filetree` already uses. `true`: a floating window
  -- instead, absolutely positioned flush against the requested edge
  -- (spanning the full opposite dimension — the whole editor height for
  -- a left/right sidebar, the whole width for top/bottom) and entirely
  -- independent of other windows — nothing else resizes to make room
  -- for it, and it doesn't get squeezed by them either. `mep.
  -- activitybar` opts into this for its own bar/panels ("a popup
  -- buffer", not a normal one).
  float = false,
  -- Floating-window border (`opts.float = true` only — ignored for a
  -- real split, which has no border of its own to configure).
  border = 'rounded',
  -- `opts.float = true` only: additionally inset the anchored edge by
  -- this many columns/rows, so this floating sidebar stacks *next to*
  -- another fixed floating element already sitting on the true screen
  -- edge (e.g. `mep.activitybar`'s icon-button bar) rather than
  -- underneath/overlapping it. 0 means "anchor flush against the real
  -- screen edge", the plain single-sidebar case.
  edge_offset = 0,
  -- Slide open/close by ramping the window's width (left/right) or
  -- height (top/bottom) from 0 up to (or down from) its target over
  -- `animate_steps` ticks, `animate_ms` apart — about as close to real
  -- animation as a character-grid terminal UI gets. Set to `false` for
  -- an instant open/close.
  animate = true,
  animate_ms = 12,
  animate_steps = 8,
  -- How many columns/rows `increase_size`/`decrease_size` (and
  -- `Sidebar:resize(delta)`'s own default `delta`) change the size by.
  resize_step = 5,
  -- Sizing floor `resize`/animation won't shrink below.
  min_size = 5,
  -- Whether `open()` leaves keyboard focus in the new window (the
  -- default — matches a real split's own natural behavior) or hands it
  -- straight back to whatever window was current beforehand (`mep.git.
  -- sidebar`'s own choice: a status panel you glance at while still
  -- typing in your actual buffer, not one that interrupts it — switch
  -- into it, e.g. `<C-w>w`, when you actually want to use its
  -- keymaps/widgets).
  focus = true,
  keymaps = {
    -- Run the widget/toggle the section header under the cursor.
    activate = { '<CR>' },
    close = { 'q' },
    increase_size = { '+', '=' },
    decrease_size = { '-' },
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

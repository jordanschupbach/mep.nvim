local M = {}

M.defaults = {
  -- Auto-attach the gutter (signs + hunk tracking) to a normal,
  -- file-backed buffer on BufEnter/BufReadPost, recomputing (debounced)
  -- on TextChanged/TextChangedI/BufWritePost. `false` registers nothing
  -- — `mep.git.gutter.attach(bufnr)` still works called by hand.
  enable = true,
  debounce_ms = 200,
  -- What the buffer is diffed against for hunks/signs: 'HEAD' (the
  -- default) marks every uncommitted change, staged or not; 'index'
  -- diffs against the staged blob instead (`git show :file`), so
  -- already-staged changes show no signs — gitsigns' own default. Any
  -- other git revision ('HEAD~1', a sha, a branch) also works.
  base = 'HEAD',
  -- Sign-column marker + highlight group per `mep.git.diff.sign_rows`
  -- kind. `text` is truncated to `signcolumn`'s own 2-cell width by
  -- Neovim itself if longer.
  signs = {
    add = { text = '+', hl = 'MepGitAdd' },
    change = { text = '~', hl = 'MepGitChange' },
    delete = { text = '_', hl = 'MepGitDelete' },
    topdelete = { text = '‾', hl = 'MepGitDelete' },
    changedelete = { text = '~', hl = 'MepGitChangeDelete' },
  },
  keymaps = {
    -- Buffer-local, bound wherever the gutter is attached.
    next_hunk = { ']c', ']g' },
    prev_hunk = { '[c', '[g' },
    stage_hunk = { '<leader>hs' },
    reset_hunk = { '<leader>hr' },
    preview_hunk = { '<leader>hp' },
    -- Global: open the git panel as an ad hoc split of the current
    -- window (the default — a real buffer in a real window, no floating
    -- panel), or docked/floating flush against an editor edge instead —
    -- same content (`mep.git.sidebar.sections()`), two presentations;
    -- opening one closes the other if it's open.
    toggle_sidebar = { '<leader>gg' },
    toggle_sidebar_dock = { '<leader>gG' },
  },
  sidebar = {
    position = 'right',
    width = 42,
    height = 15,
    border = 'rounded',
    animate = true,
    -- Buffer-local to the sidebar window itself, on top of
    -- `mep.sidebar`'s own `<CR>` (open the file/hunk under the cursor)
    -- and `q` (close) — nothing to configure for those two here.
    keymaps = {
      refresh = { 'R' },
      -- Swaps the panel into a real, editable commit-message buffer
      -- (see `mep.git.sidebar`'s `open_commit_compose`) — `ZZ`/`ZQ`
      -- (not configurable here, Vim's own write-and-quit/quit-without-
      -- writing convention) commit/cancel it.
      commit = { 'c' },
      stage = { 's' },
      unstage = { 'u' },
      discard = { 'X' },
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

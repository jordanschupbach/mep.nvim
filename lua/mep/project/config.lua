local M = {}

M.defaults = {
  -- Where the project list is persisted as JSON. `nil` means
  -- `stdpath('data') .. '/mep_projects.json'`, resolved lazily (not
  -- here — see mep.project.project) so requiring this module never
  -- touches the filesystem just by loading.
  persist_path = nil,
  -- Candidate README file names, checked in order, for what `M.picker`
  -- previews and `on_select` opens after `cd`ing into a project — the
  -- first one that actually exists in that project's directory wins.
  readme_names = { 'README.org', 'README.md' },
  -- What else `on_select` sets up alongside the README, both on by
  -- default: `mep.filetree` rooted at the project (left), a `:terminal`
  -- (below the README) — focus ends back on the README either way.
  open_filetree = true,
  open_terminal = true,
  -- The terminal's share of the README window's own height (before
  -- splitting) — 0.3 means the terminal ends up at roughly 30%, the
  -- README the remaining ~70%. Only consulted when `open_terminal` is
  -- true.
  terminal_height_ratio = 0.3,
  keymaps = {
    -- Add the current directory to the project list, from inside the
    -- picker prompt.
    add = { '<C-a>' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

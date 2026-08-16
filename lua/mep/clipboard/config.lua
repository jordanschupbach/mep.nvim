local M = {}

M.defaults = {
  enable = true,
  -- `vim.o.clipboard = 'unnamedplus'` — yank/delete/paste use the
  -- system clipboard register (`"+`) without needing `"+y`/`"+p`
  -- explicitly. `false` leaves `'clipboard'` exactly as whatever
  -- already set it.
  unnamedplus = true,
  osc52 = {
    -- Wire `vim.g.clipboard` to Neovim's own builtin OSC 52 provider
    -- (`vim.ui.clipboard.osc52` — the terminal-escape-sequence
    -- clipboard protocol, no local clipboard tool needed) whenever
    -- `mep.clipboard.platform.is_ssh()` is true *and* `platform.
    -- has_local_tool()` is false — an SSH session with no
    -- pbcopy/wl-copy/xclip/xsel/win32yank.exe reachable on `PATH`, the
    -- one case Neovim's own native clipboard provider (`:help
    -- provider-clipboard`) can't already handle by itself. `false`
    -- skips this regardless of session/tool detection.
    enable = true,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

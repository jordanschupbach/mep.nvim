local M = {}

M.defaults = {
  -- Key sequences that open the popup when pressed — each becomes its
  -- own keymap (in every configured `modes`) via setup(). Empty by
  -- default would mean "does nothing"; `<leader>` is the one sensible
  -- default vocabulary of "prefix keys a user actually wants to
  -- discover", the same reasoning mep.picker's own defaults lean on for
  -- its own well-known keys.
  triggers = { '<leader>' },
  -- Modes `triggers` are bound in, and that mep.whichkey looks up
  -- mappings for.
  modes = { 'n' },
  -- Where the popup appears: `'bottom'` (default — spans the full
  -- editor width, anchored above the command line, entries laid out in
  -- a column-major grid to make use of that width — real which-key.nvim's
  -- own default look) or `'top'` (same, anchored at row 0) or `'cursor'`
  -- (a small single-column list right under the cursor, this library's
  -- original v1 behavior).
  position = 'bottom',
  -- Floating popup border style, passed straight through to
  -- `nvim_open_win`. `'none'` removes the 1-cell padding `'bottom'`/
  -- `'top'` otherwise reserve for it on every side.
  border = 'rounded',
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

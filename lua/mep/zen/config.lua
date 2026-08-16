local M = {}

M.defaults = {
  -- The centered buffer's own target width once zen mode adds side
  -- padding windows — real content narrower than this just leaves
  -- whitespace either side of it, the same as any fixed-width editor
  -- column. Ignored (no padding added) if the window is already
  -- narrower than this.
  width = 90,
  -- Individually toggle which pieces zen mode touches — same
  -- "everything independently disableable" convention mep.sanity uses.
  hide = {
    activitybar = true,
    filetree = true,
    symbols = true,
    gutter = true,
    chrome = true,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

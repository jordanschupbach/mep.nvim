--- Window-local gutter suppression for zen mode — the same save/restore
--- idiom `mep.dashboard.ui` uses for its own gutter suppression
--- (`number`/`relativenumber`/`signcolumn`, `vim.wo[win]` rather than
--- `vim.o` so it never touches any other window).
local M = {}

local OPTS = { 'number', 'relativenumber', 'signcolumn' }

--- Strip `win`'s gutter and return the previous values so `M.restore`
--- can put them back.
function M.suppress(win)
  local saved = {}
  for _, opt in ipairs(OPTS) do
    saved[opt] = vim.wo[win][opt]
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  return saved
end

--- Undo `M.suppress`: put `win`'s saved option values back. A no-op if
--- `win` has since closed.
function M.restore(win, saved)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  for _, opt in ipairs(OPTS) do
    vim.wo[win][opt] = saved[opt]
  end
end

return M

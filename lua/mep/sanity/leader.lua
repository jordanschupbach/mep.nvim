--- Sets Neovim's <leader> and <localleader> keys.
local M = {}

--- Apply the leader-key setting. `key` is the character to use for both
--- mapleader and maplocalleader; `false` or `nil` leaves them untouched
--- (e.g. because the user already set their own before calling setup()).
function M.apply(key)
  if not key then
    return
  end
  vim.g.mapleader = key
  vim.g.maplocalleader = key
end

return M

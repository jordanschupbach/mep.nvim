--- Tab-management keymaps: new tab, and jump-straight-to-tab-N.
local M = {}

local function map(lhs_list, cmd, desc)
  for _, lhs in ipairs(lhs_list or {}) do
    vim.keymap.set('n', lhs, '<cmd>' .. cmd .. '<cr>', { desc = desc })
  end
end

--- Bind `keymaps.new` (a plain list of lhs strings, all bound to
--- `:tabnew`) and `keymaps.select` (positional — `select[i]` jumps
--- straight to tab `i`, `:tabnext i`) — `mep.sanity.config.defaults.
--- tabs.keymaps`'s own shape. `false`/`nil` (the whole table, or either
--- list left empty) leaves that action unbound.
function M.apply(keymaps)
  if not keymaps then
    return
  end
  map(keymaps.new, 'tabnew', 'mep.sanity: new tab')
  for i, lhs in ipairs(keymaps.select or {}) do
    vim.keymap.set('n', lhs, '<cmd>tabnext ' .. i .. '<cr>', { desc = 'mep.sanity: go to tab ' .. i })
  end
end

return M

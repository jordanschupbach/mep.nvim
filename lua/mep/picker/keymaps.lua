--- Global trigger keymaps: bind a normal-mode key outside the picker's
--- own prompt window (see engine.lua for those) to open one of the
--- built-in pickers, e.g. replacing Neovim's native `/` search with
--- mep.picker.buffer_search().
local M = {}

local function map(lhs_list, fn, desc)
  for _, lhs in ipairs(lhs_list or {}) do
    vim.keymap.set('n', lhs, fn, { desc = desc })
  end
end

--- Bind `triggers.buffer_search` (a plain list of lhs strings, from
--- mep.picker.config.defaults.triggers) to open the current-buffer
--- search picker. `false`/`nil` (the whole table, or an empty list)
--- leaves it unbound. Requires `mep.picker.picker` lazily, inside the
--- callback, to avoid a require-cycle with the aggregator that wires
--- this module up.
function M.apply(triggers)
  if not triggers then
    return
  end
  map(triggers.buffer_search, function()
    require('mep.picker').buffer_search()
  end, 'mep.picker: search buffer')
end

return M

local M = {}

M.defaults = {
  -- query-input debounce, split by source kind: static sources (find_files,
  -- buffer_search) filter an in-memory list and can react almost
  -- instantly; dynamic sources (live_grep) spawn a process per query and
  -- want a longer debounce so they don't do that on every keystroke.
  debounce_ms = {
    static = 20,
    dynamic = 120,
  },
  keymaps = {
    select = { '<CR>' },
    close = { '<Esc>', '<C-c>' },
    next = { '<C-n>', '<Down>', '<C-j>' },
    prev = { '<C-p>', '<Up>', '<C-k>' },
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

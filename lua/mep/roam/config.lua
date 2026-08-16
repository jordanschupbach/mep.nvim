local M = {}

M.defaults = {
  -- Directories notes live in — `roam_dirs[1]` is also where `:MepRoamToday`
  -- files daily notes (its own `daily/` subdirectory) and new notes get
  -- created. Every `.org` file found recursively under any of these
  -- (not just the first) counts as a note for search/insert/backlinks.
  roam_dirs = {},
  -- `mep.org.capture`'s own placeholder syntax (`%T`/`%?`/`%^{PROMPT}`/
  -- ...) — expanded once, only when `:MepRoamToday` actually creates a
  -- new file; an existing daily note opens as-is, untouched.
  daily_template = '#+TITLE: %T\n\n* Journal\n%?',
  keymaps = {
    -- Fuzzy-search notes, inserting a [[id:...][title]] link at the
    -- cursor for whichever one you pick.
    insert = { '<leader>rf' },
    -- Toggle the backlinks panel for the current note.
    backlinks = { '<leader>rb' },
    -- Open (creating if missing) today's daily note.
    today = { '<leader>rt' },
    -- Prompt for a title and create a new note.
    new_note = { '<leader>rc' },
  },
  -- mep.sidebar geometry for the backlinks panel — same shape as
  -- mep.dap.config.defaults.sidebar.
  sidebar = {
    position = 'right',
    width = 42,
    height = 15,
    border = 'rounded',
    animate = true,
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

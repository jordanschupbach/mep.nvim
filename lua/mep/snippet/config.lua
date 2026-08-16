local M = {}

M.defaults = {
  -- Whether <Tab>/<S-Tab> are bound at all — a global insert-mode
  -- override (more invasive than most of this project's keymaps), so
  -- it's independently opt-outable even though it's the default (the
  -- TODO this library implements explicitly asks for "navigated via
  -- <Tab>/<S-Tab>").
  tab_keymap = true,
  -- Whether `mep.snippet.langs.*`'s curated per-language snippet sets
  -- (Lua/Python/Go/Rust/C/JS/TS/shell) are registered at `setup()` time.
  -- `false` starts with an empty registry — supply entirely your own via
  -- `mep.snippet.add(filetype, {...})` instead.
  builtin_langs = true,
  keymaps = {
    -- Global: browse/insert a snippet for the current buffer's filetype.
    picker = { '<leader>yy' },
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

local M = {}

M.defaults = {
  -- 'background' paints the matched text itself as a background swatch
  -- (foreground auto-picked black/white for contrast); 'swatch' instead
  -- overlays a single colored character (`swatch_char`) just before the
  -- match, leaving the original text's own highlighting untouched.
  mode = 'background',
  swatch_char = '●',
  -- Which filetypes to activate in — `false`/`nil` (the default) means
  -- every filetype; a list (e.g. `{ 'css', 'html', 'lua' }`) restricts
  -- to just those.
  filetypes = false,
  -- Recompute debounce, same `TextChanged`/`TextChangedI`/`BufWritePost`
  -- trigger set `mep.markdown.gutter`'s own attach/detach lifecycle
  -- uses.
  debounce_ms = 150,
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys, consistent with every other library's
-- config module — this one happens to have no keymap-shaped strings to
-- expand, but M.options still needs to exist as the resolved-state
-- table every other module in this project reads.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

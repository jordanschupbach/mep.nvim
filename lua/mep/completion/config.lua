local M = {}

M.defaults = {
  -- Which registered sources (mep.completion.completion.sources) to
  -- query, in priority order — first-listed wins on a duplicate `word`
  -- across sources. An unrecognized name is skipped with a warning at
  -- setup() time, not a hard error.
  sources = { 'lsp', 'buffer', 'path', 'snippet' },
  -- How long to wait, after the buffer stops changing, before querying
  -- sources — mep.picker's own dynamic-source debounce idea, applied
  -- here.
  debounce_ms = 80,
  -- Don't bother triggering until at least this many keyword characters
  -- have been typed (avoids firing on every single keystroke from an
  -- empty prefix). The manual trigger keymap ignores this and always
  -- fires.
  min_chars = 1,
  -- Cap on how many merged (deduped) items get shown at once.
  max_items = 50,
  -- Whether typing (`TextChangedI`, debounced by `debounce_ms`) opens
  -- the popup on its own. Set to `false` to only ever show it via the
  -- `keymaps.trigger` keymap.
  auto_trigger = true,
  -- Applied to (global) 'completeopt' by `engine.enable()`, restored to
  -- whatever it was on `engine.disable()`. `noinsert` is the flag that
  -- makes this "manual accept": the popup's first match is highlighted
  -- but never written into the buffer on its own — only `<C-y>`
  -- (Neovim's own built-in insert-mode "accept" key, nothing to bind
  -- for it) commits it. Without `noinsert`, Vim's default ins-completion
  -- behavior auto-inserts the top match as you keep typing, which reads
  -- as completion "happening automatically".
  completeopt = { 'menu', 'menuone', 'noinsert' },
  keymaps = {
    -- Manually invoke completion right now, regardless of min_chars.
    -- Everything else — <C-n>/<C-p> to navigate the popup, <C-y> to
    -- accept, <C-e> to abort — is Neovim's own built-in insert-mode
    -- completion keys, already there for free once `vim.fn.complete()`
    -- has populated the menu; nothing to bind for those.
    trigger = { '<C-Space>' },
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

local M = {}

M.defaults = {
  -- Popup toasts: which screen corner they stack against
  -- ('top-right'/'top-left'/'bottom-right'/'bottom-left'), how wide
  -- they're allowed to grow before wrapping, how far they sit from the
  -- true screen edge (`margin`), and the gap between two stacked
  -- toasts (`spacing`). Newest toast lands right at the corner; older
  -- ones get pushed away from it as more arrive.
  position = 'top-right',
  min_width = 30,
  max_width = 60,
  -- Left/right inner padding (in columns) between a toast's border and
  -- its text.
  padding = 1,
  margin = 1,
  spacing = 1,
  border = 'rounded',
  -- At most this many toasts stack at once — the oldest is closed
  -- immediately (not queued) to make room for a new one past this
  -- limit, same as nvim-notify's own default behavior.
  max_visible = 5,
  -- One glyph per `vim.log.levels` value, prefixed to a toast's own
  -- header line and used as a widget `icon` in the history panel's
  -- sections. Plain Unicode, not Nerd Font private-use codepoints (see
  -- `mep.icons.config.defaults.style`'s own reasoning) — these render
  -- correctly with no special font required; override with Nerd Font
  -- glyphs yourself if you have one selected.
  icons = {
    [vim.log.levels.ERROR] = '✗',
    [vim.log.levels.WARN] = '⚠',
    [vim.log.levels.INFO] = 'ℹ',
    [vim.log.levels.DEBUG] = '·',
    [vim.log.levels.TRACE] = '·',
  },
  -- How long (ms) a toast stays up before auto-dismissing, per level —
  -- errors/warnings linger longer than routine info/debug noise. `0`
  -- (or `false`) means "never auto-dismiss" (stays until `dismiss_all`/
  -- max_visible eviction closes it).
  timeout = {
    [vim.log.levels.ERROR] = 8000,
    [vim.log.levels.WARN] = 6000,
    [vim.log.levels.INFO] = 4000,
    [vim.log.levels.DEBUG] = 3000,
    [vim.log.levels.TRACE] = 3000,
  },
  -- History: oldest entries drop off once this many are buffered.
  max_entries = 200,
  -- The standalone history sidebar `M.toggle()` opens (see mep.
  -- notify.notify) — independent of `mep.activitybar`'s own panel
  -- sizing, which an activitybar-embedded notifications button uses
  -- instead (its own position/panel_width/float/border/animate,
  -- `mep.activitybar.git`'s exact "same content, differently-sized
  -- host sidebar" precedent).
  panel = {
    position = 'right',
    width = 50,
    float = true,
    border = 'rounded',
    animate = true,
  },
  keymaps = {
    -- Dismiss the notification under the cursor, in the history panel
    -- — on top of the mep.sidebar's own default `<CR>`/click, which
    -- already runs a widget's `on_click` (also a dismiss) either way.
    dismiss = { 'd', 'x' },
    clear = { 'C' },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

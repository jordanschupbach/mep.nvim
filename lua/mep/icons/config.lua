local M = {}

M.defaults = {
  -- 'nerd_font' (default): monochrome Nerd Font glyphs (private-use-area
  --   codepoints, the same ones nvim-web-devicons ships), used by
  --   mep.filetree by default. Only looks right if you actually have a
  --   Nerd Font installed and selected in your terminal/GUI — set this to
  --   'emoji' if you don't.
  -- 'emoji': broad file-type coverage using standard Unicode emoji —
  --   renders correctly on virtually any system without a special font
  --   installed.
  -- 'ascii': plain 7-bit fallback (no per-type icons, just generic
  --   file/directory/expand markers) for terminals with poor Unicode
  --   support.
  style = 'nerd_font',

  -- Per-style overrides layered on top of the built-in tables, e.g.:
  --   overrides = { emoji = { by_extension = { lua = '🌛' } } }
  overrides = {},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

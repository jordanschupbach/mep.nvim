--- Human-readable names for Neovim's `mode(1)` return values — `:help
--- mode()` explicitly recommends comparing only the leading
--- character(s) of the full-mode string, not the whole thing, since new
--- more-specific codes get added over time; this does the same.
local M = {}

-- Checked in order, most specific prefix first, so `'nt'` (Normal in a
-- terminal buffer, entered via `<C-\><C-n>`) matches before the bare
-- `'n'` (plain Normal) it would otherwise also match as a prefix of.
local PREFIXES = {
  { 'nt', 'Normal (Terminal)' },
  { 'n', 'Normal' },
  { 'v', 'Visual' },
  { 'V', 'Visual' },
  { '\22', 'Visual' }, -- CTRL-V: blockwise Visual
  { 's', 'Select' },
  { 'S', 'Select' },
  { '\19', 'Select' }, -- CTRL-S: blockwise Select
  { 'i', 'Insert' },
  { 'R', 'Replace' },
  { 'c', 'Command' },
  { 't', 'Terminal' },
  { '!', 'Shell' },
  { 'r', 'Prompt' },
}

--- The current mode (`vim.fn.mode(1)`), translated to a short display
--- name — falls back to the raw code itself for anything `PREFIXES`
--- doesn't recognize.
function M.name()
  local code = vim.fn.mode(1)
  for _, entry in ipairs(PREFIXES) do
    if vim.startswith(code, entry[1]) then
      return entry[2]
    end
  end
  return code
end

return M

--- Inline diagnostics as a single colored circle at the end of each
--- diagnostic-bearing line (highest severity among that line's
--- diagnostics wins the color), replacing Neovim's native `vim.
--- diagnostic` virtual_text entirely (`M.setup` forces `virtual_text =
--- false`) rather than rendering alongside it. `<leader>ld` (configurable)
--- expands the line under the cursor into `vim.diagnostic.open_float`,
--- Neovim's own line-scoped floating window — no hand-rolled popup.
---
--- Pure-Lua extmark bookkeeping recomputed on `DiagnosticChanged`, the
--- same pattern `mep.org.blockhl`/`mep.dap.breakpoints`/`mep.git.gutter`
--- each already use for their own per-line sign/highlight state.
local config = require('mep.diagnostics.config')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_diagnostics_circles')
local augroup = nil

--- The single highest-severity diagnostic per 0-indexed line in
--- `bufnr` (`vim.diagnostic.severity` is ordered low-to-high-priority —
--- `ERROR` is `1`, the lowest number — so "highest severity" is the
--- minimum `.severity` value seen for that line).
local function highest_severity_per_line(bufnr)
  local by_line = {}
  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    local current = by_line[d.lnum]
    if not current or d.severity < current.severity then
      by_line[d.lnum] = d
    end
  end
  return by_line
end

--- Clear every circle extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute circle extmarks for every diagnostic-bearing line in
--- `bufnr`, replacing whatever was there before.
function M.apply(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.clear(bufnr)
  local options = config.options
  for lnum, d in pairs(highest_severity_per_line(bufnr)) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
      virt_text = { { options.circle, options.hl[d.severity] } },
      virt_text_pos = 'eol',
    })
  end
end

--- Open Neovim's own line-scoped diagnostic float for `lnum`
--- (0-indexed) in `bufnr`, defaulting to the current buffer/cursor line
--- if either is omitted.
function M.show_line_float(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or (vim.api.nvim_win_get_cursor(0)[1] - 1)
  vim.diagnostic.open_float(bufnr, {
    scope = 'line',
    pos = { lnum, 0 },
    border = config.options.float.border,
  })
end

--- Configure mep.diagnostics: `enable`, `circle`, `hl`, `float`,
--- `keymaps` (see mep.diagnostics.config.defaults). When enabled
--- (the default), forces `vim.diagnostic.config({ virtual_text = false
--- })` so the circles fully replace native virtual text regardless of
--- whether `mep.lsp.setup()` (or your own `vim.diagnostic.config` call)
--- ran before or after this — call `mep.diagnostics.setup()` after
--- `mep.lsp.setup()` if you use both, so this override is the one that
--- sticks (this is exactly the ordering `require('mep').setup()`'s own
--- library list uses: `diagnostics` right after `lsp`). `enable = false`
--- leaves `vim.diagnostic` exactly as whatever already configured it.
function M.setup(opts)
  local options = config.setup(opts)

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end

  if not options.enable then
    return options
  end

  vim.diagnostic.config({ virtual_text = false })

  augroup = vim.api.nvim_create_augroup('MepDiagnostics', { clear = true })
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = augroup,
    callback = function(args)
      M.apply(args.buf)
    end,
  })

  for _, lhs in ipairs(options.keymaps.show_line) do
    vim.keymap.set('n', lhs, function()
      M.show_line_float(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1)
    end, { desc = 'mep.diagnostics: show diagnostics for this line' })
  end

  return options
end

--- Test/dev-only: drop the `DiagnosticChanged` augroup so the next
--- `setup()` starts clean.
function M._reset()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
end

return M

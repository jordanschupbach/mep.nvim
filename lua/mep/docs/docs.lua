--- Aggregator for mep's docs library: docstring generation
--- (`mep.docs.generate`, LSP signature help when attached, a per-
--- filetype regex fallback otherwise) and external doc lookup
--- (`mep.docs.lookup`, pure link construction, no scraping).
local config = require('mep.docs.config')
local generate = require('mep.docs.generate')
local lookup = require('mep.docs.lookup')
local templates = require('mep.docs.templates')

local M = {}
M.templates = templates

--- Insert a doc-comment skeleton for the function on the current
--- cursor line.
function M.generate()
  generate.generate(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
end

--- Open external documentation for the word under the cursor.
function M.lookup()
  lookup.lookup(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
end

--- Configure mep.docs: `doc_hints` (extra/override devdocs.io doc-set
--- hints) and `keymaps.generate`/`keymaps.lookup` (global, not
--- filetype-scoped — both check the current buffer's filetype at press
--- time and notify rather than erroring if it has no curated template).
--- Works with sensible defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.generate) do
    vim.keymap.set('n', lhs, M.generate, { desc = 'mep.docs: generate a docstring skeleton' })
  end
  for _, lhs in ipairs(options.keymaps.lookup) do
    vim.keymap.set('n', lhs, M.lookup, { desc = 'mep.docs: open external documentation for the word under cursor' })
  end
  return options
end

return M

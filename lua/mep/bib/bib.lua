--- org-ref-like citation reference picker: finds `.bib` files (`mep.
--- bib.finder`), parses them (`mep.bib.parser`), and lets you browse/
--- insert a `[cite:@key]` (org-cite syntax) reference at the cursor via
--- `mep.picker`. Its own library, not folded into `mep.org`, since
--- citation lookup is useful from any buffer type, not just org-mode
--- (the same "own top-level library, other libraries soft-depend on
--- it" shape `mep.snippet` uses).
---
--- **Prerequisite**: `<localleader>ir` (the default `keymaps.insert`)
--- only resolves the way you'd expect once `vim.g.maplocalleader` is
--- actually set to something — `mep.bib.setup()` deliberately does NOT
--- set it itself (a citation library silently changing a global Neovim
--- option as a side effect of its own setup would be a surprising,
--- hard-to-trace side effect for anyone who sets `maplocalleader`
--- elsewhere already), matching how `mep.sanity.leader` treats leader-
--- key changes as the user's own explicit opt-in, not any single
--- feature's. Set `vim.g.maplocalleader` yourself before calling
--- `require('mep').setup(...)`, same as any Neovim config needing
--- `<localleader>`-based mappings.
local config = require('mep.bib.config')
local parser = require('mep.bib.parser')
local finder = require('mep.bib.finder')

local M = {}
M.parser = parser
M.finder = finder

--- Every parsed entry across every `.bib` file found for `bufnr`
--- (`mep.bib.finder.find_bib_files`), flattened into one list.
function M.entries(bufnr)
  local entries = {}
  for _, path in ipairs(finder.find_bib_files(bufnr)) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      vim.list_extend(entries, parser.parse(table.concat(lines, '\n')))
    end
  end
  return entries
end

local function display(entry)
  local f = entry.fields
  local title = f.title or '(no title)'
  local who = f.author or f.editor
  local bits = {}
  if who then
    bits[#bits + 1] = who
  end
  if f.year then
    bits[#bits + 1] = f.year
  end
  local suffix = #bits > 0 and (' (' .. table.concat(bits, ', ') .. ')') or ''
  return entry.key .. ' — ' .. title .. suffix
end

--- Browse every citation entry found for the current buffer and insert
--- `[cite:@key]` at the cursor on select.
function M.picker()
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  require('mep.picker').start({
    prompt_title = 'Citations',
    items = M.entries(bufnr),
    entry_to_string = display,
    on_select = function(entry)
      local cursor = vim.api.nvim_win_get_cursor(win)
      local lnum, col = cursor[1], cursor[2]
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
      local citation = '[cite:@' .. entry.key .. ']'
      vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { line:sub(1, col) .. citation .. line:sub(col + 1) })
    end,
  })
end

--- Configure mep.bib: `keymaps.insert` (see mep.bib.config.defaults).
--- Works with sensible defaults even if this is never called — see
--- this module's own header comment on the `maplocalleader`
--- prerequisite for the default keymap to resolve usefully.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.insert) do
    vim.keymap.set('n', lhs, M.picker, { desc = 'mep.bib: insert citation reference' })
  end
  return options
end

return M

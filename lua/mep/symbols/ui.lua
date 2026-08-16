--- Window/buffer management and rendering for mep.symbols: a real
--- vertical split of the *current* window (`aboveleft`/`belowright`,
--- not `topleft`/`botright` — see mep.symbols.symbols.open's own header
--- comment for why this differs from mep.filetree's single persistent,
--- tabpage-edge-anchored panel).
local M = {}

local kind_ns = vim.api.nvim_create_namespace('mep_symbols_kind')

local SPLIT_CMD = {
  left = 'aboveleft',
  right = 'belowright',
}

--- Split the *current* window vertically into `width` columns on
--- `position` ('left'/'right'), with a fresh scratch buffer in the new
--- half. Returns `buf, win`.
function M.create_window(width, position)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mep-symbols'

  vim.cmd((SPLIT_CMD[position] or SPLIT_CMD.right) .. ' vertical ' .. tostring(width) .. 'split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  -- Otherwise fair game for Neovim's 'equalalways' (on by default), same
  -- reasoning mep.filetree.ui/mep.sidebar.engine already document.
  vim.wo[win].winfixwidth = true
  vim.wo[win].winbar = '%#MepSymbolsTitle# Symbols'

  return buf, win
end

function M.close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

--- Render `symbols` (mep.symbols.lsp.flatten's own shape) into `buf`,
--- one per line, indented 2 columns per depth as `[KindName] name`.
--- `err` (from a failed/no-client M.request) shows a single message
--- line instead, with no jump targets — same for `symbols == nil` or an
--- empty list ("no symbols in this file", not an error). Returns
--- `activatable`: a 1-based line number -> symbol table map for every
--- symbol line (empty when there's only a message).
function M.render(buf, symbols, err)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end

  local lines = {}
  local marks = {}
  local activatable = {}

  if err then
    lines[1] = err
  elseif not symbols or #symbols == 0 then
    lines[1] = 'No symbols'
  else
    for _, sym in ipairs(symbols) do
      local indent = string.rep('  ', sym.depth)
      local kind_tag = '[' .. sym.kind_name .. ']'
      lines[#lines + 1] = indent .. kind_tag .. ' ' .. sym.name
      local lnum = #lines
      marks[#marks + 1] = { lnum = lnum - 1, col_start = #indent, col_end = #indent + #kind_tag, hl = 'MepSymbolsKind' }
      activatable[lnum] = sym
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, kind_ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_add_highlight, buf, kind_ns, m.hl, m.lnum, m.col_start, m.col_end)
  end
  vim.bo[buf].modifiable = false

  return activatable
end

return M

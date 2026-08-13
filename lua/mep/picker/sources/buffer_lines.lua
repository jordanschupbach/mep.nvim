--- Within-document search source: fuzzy-find non-blank lines of a buffer
--- (current buffer by default).
local preview = require('mep.picker.preview')

local M = {}

function M.picker_opts(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local winid = opts.winid or vim.api.nvim_get_current_win()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local items = {}
  for i, line in ipairs(lines) do
    if line:match('%S') then
      items[#items + 1] = { lnum = i, display = string.format('%4d: %s', i, line) }
    end
  end

  return {
    prompt_title = 'Search Buffer: ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t'),
    items = items,
    entry_to_string = function(item)
      return item.display
    end,
    preview = function(item, buf, win)
      preview.show_buffer(buf, win, bufnr, item.lnum)
    end,
    on_select = function(item)
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_set_current_win(winid)
      end
      pcall(vim.api.nvim_win_set_cursor, winid, { item.lnum, 0 })
      pcall(vim.api.nvim_win_call, winid, function()
        vim.cmd('normal! zz')
      end)
    end,
  }
end

return M

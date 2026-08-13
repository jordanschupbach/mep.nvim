--- Open-buffers picker source: fuzzy-find among the current session's
--- listed, loaded buffers (the same set `:ls`/`:buffers` shows), most
--- recently used first.
local preview = require('mep.picker.preview')

local M = {}

--- `bufnr`'s display name: its path relative to cwd/home (`:~:.`, the
--- same abbreviation `:ls` itself uses), or `[No Name]` for a buffer
--- that was never given one — with a trailing `●` while it has unsaved
--- changes, same convention as `mep.window.panes`'s own tab labels.
local function display_name(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  name = (name == '') and '[No Name]' or vim.fn.fnamemodify(name, ':~:.')
  if vim.bo[bufnr].modified then
    name = name .. ' ●'
  end
  return name
end

function M.picker_opts(opts)
  opts = opts or {}

  local items = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_loaded(bufnr) then
      local info = vim.fn.getbufinfo(bufnr)[1]
      items[#items + 1] = {
        bufnr = bufnr,
        lnum = (info and info.lnum and info.lnum > 0) and info.lnum or 1,
        lastused = (info and info.lastused) or 0,
        display = display_name(bufnr),
      }
    end
  end
  table.sort(items, function(a, b)
    return a.lastused > b.lastused
  end)

  return {
    prompt_title = 'Buffers',
    items = items,
    entry_to_string = function(item)
      return item.display
    end,
    preview = function(item, buf, win)
      preview.show_buffer(buf, win, item.bufnr, item.lnum)
    end,
    on_select = function(item)
      local win = vim.fn.bufwinid(item.bufnr)
      if win ~= -1 then
        vim.api.nvim_set_current_win(win)
      else
        vim.api.nvim_set_current_buf(item.bufnr)
      end
    end,
  }
end

return M

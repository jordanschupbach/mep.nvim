--- Local-problems picker source: fuzzy-find `mep.leetcode.local.list`'s
--- own problem list, `<CR>` opens the file.
local local_mod = require('mep.leetcode.local')
local preview = require('mep.picker.preview')

local M = {}

function M.picker_opts(problems_dir)
  local items = local_mod.list(problems_dir)
  return {
    prompt_title = 'LeetCode Problems',
    items = items,
    entry_to_string = function(item)
      local diff = (item.difficulty and item.difficulty ~= '') and (' [' .. item.difficulty .. ']') or ''
      return item.title .. diff
    end,
    preview = function(item, buf, win)
      preview.show_file(buf, win, item.path)
    end,
    on_select = function(item)
      vim.cmd('edit ' .. vim.fn.fnameescape(item.path))
    end,
  }
end

return M

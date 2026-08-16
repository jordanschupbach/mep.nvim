--- Note search-and-insert picker: fuzzy search note titles across
--- `config.options.roam_dirs`, `<CR>` inserts a `[[id:...][title]]` link
--- at the cursor for whichever one you pick — `mep.org.id.get_or_create`
--- + `mep.org.link.render` reused directly, not a separate ID/link
--- mechanism.
local notes = require('mep.roam.notes')
local link_mod = require('mep.org.link')
local preview = require('mep.picker.preview')

local M = {}

function M.picker_opts(roam_dirs)
  local items = notes.list(roam_dirs)
  return {
    prompt_title = 'Roam Notes',
    items = items,
    entry_to_string = function(item)
      return item.title
    end,
    preview = function(item, buf, win)
      preview.show_buffer(buf, win, item.bufnr, 1)
    end,
    on_select = function(item)
      local text = link_mod.render({ target = 'id:' .. item.id, description = item.title })
      vim.api.nvim_put({ text }, 'c', false, true)
    end,
  }
end

return M

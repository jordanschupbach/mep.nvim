--- Snippets picker source: every snippet registered (`mep.snippet.
--- registry`) for the current buffer's own filetype, inserted at the
--- cursor on select — a manual insert of the raw body via `mep.snippet.
--- session.expand` with `replace_len = 0` (nothing before the cursor is
--- being replaced, unlike a trigger-word expansion), not a trigger-word
--- lookup.
local M = {}

function M.picker_opts(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local win = opts.win or vim.api.nvim_get_current_win()
  local filetype = vim.bo[bufnr].filetype

  local snippet_mod = require('mep.snippet')
  local items = snippet_mod.registry.get(filetype)

  return {
    prompt_title = 'Snippets (' .. (filetype ~= '' and filetype or 'no filetype') .. ')',
    items = items,
    entry_to_string = function(item)
      local first_line = vim.split(item.body, '\n', { plain = true })[1] or ''
      return item.trigger .. '  ' .. first_line
    end,
    on_select = function(item)
      snippet_mod.session.expand(bufnr, win, 0, item.body)
    end,
  }
end

return M

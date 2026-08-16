--- New-note creation: writes `roam_dirs[1]/<slugified title>.org`, a
--- `* <title>` headline given a freshly-generated `:ID:` property
--- (`mep.org.id.get_or_create` — this project's own single ID
--- mechanism, not a separate one for roam notes).
local id_mod = require('mep.org.id')

local M = {}

--- `title` slugified for a filename: lower-cased, spaces to hyphens,
--- anything else non-alphanumeric dropped.
function M.slugify(title)
  return title:lower():gsub('%s+', '-'):gsub('[^%w%-]', '')
end

--- Create a new note file under `roam_dirs[1]` for `title`. Returns the
--- written path, or nil (with a notification) if `roam_dirs` has no
--- first entry.
function M.new_note(title, roam_dirs)
  local base = roam_dirs and roam_dirs[1]
  if not base then
    vim.notify('mep.roam: no roam_dirs configured', vim.log.levels.WARN)
    return nil
  end

  local dir = vim.fn.expand(base)
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/' .. M.slugify(title) .. '.org'

  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '* ' .. title })
  id_mod.get_or_create(bufnr, 1)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('write')
  end)
  return path
end

--- Prompt (`vim.ui.input`) for a title and `M.new_note` it, opening the
--- result. A cancelled/empty prompt creates nothing.
function M.new_note_interactive(roam_dirs)
  vim.ui.input({ prompt = 'mep.roam: note title: ' }, function(title)
    if title == nil or title == '' then
      return
    end
    local path = M.new_note(title, roam_dirs)
    if path then
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    end
  end)
end

return M

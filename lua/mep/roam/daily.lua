--- Daily/journal notes: `roam_dirs[1]/daily/YYYY-MM-DD.org`, created
--- (with `config.options.daily_template`'s own expanded content —
--- `mep.org.capture`'s existing placeholder templating reused directly,
--- not a separate one) the first time today's note is opened; an
--- existing file just opens as-is.
local capture = require('mep.org.capture')

local M = {}

--- Today's daily-note path, or nil if `roam_dirs` has no first entry.
function M.today_path(roam_dirs)
  local base = roam_dirs and roam_dirs[1]
  if not base then
    return nil
  end
  return vim.fn.expand(base) .. '/daily/' .. os.date('%Y-%m-%d') .. '.org'
end

--- Open (creating if missing) today's daily note under `roam_dirs[1]`,
--- expanding `template` (`mep.org.capture`'s own placeholder syntax)
--- into a brand-new file's initial content. A no-op (with a
--- notification) if `roam_dirs` has no first entry.
function M.open_today(roam_dirs, template)
  local path = M.today_path(roam_dirs)
  if not path then
    vim.notify('mep.roam: no roam_dirs configured', vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(path) == 1 then
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    return
  end

  capture.expand(template, {}, function(text, cursor_offset)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(text, '\n', { plain = true }))
    if cursor_offset then
      local lnum, col = capture.offset_to_pos(text, cursor_offset)
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
    end
    vim.cmd('write')
  end)
end

return M

--- Renders the currently-selected item into the preview sidebar: file
--- content with filetype detection (for built-in syntax/treesitter
--- highlighting) or a snapshot of a live buffer, with the target line
--- centered and highlighted.
local M = {}

local line_ns = vim.api.nvim_create_namespace('mep_picker_preview_line')

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function focus_line(win, buf, lnum, total_lines)
  lnum = math.max(1, math.min(lnum or 1, math.max(1, total_lines)))
  vim.api.nvim_buf_clear_namespace(buf, line_ns, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, buf, line_ns, 'MepPreviewLine', lnum - 1, 0, -1)
  if vim.api.nvim_win_is_valid(win) then
    -- Setting `filetype` above (for syntax/treesitter highlighting) can
    -- trigger a FileType autocmd that turns on folding for this window
    -- (e.g. mep.org's headline foldexpr) — undesirable in a preview pane,
    -- where the whole point is to show surrounding context around the
    -- matched line, not a buffer collapsed to its default foldlevel.
    -- Re-assert this on every call, since it's window-local and each new
    -- preview re-triggers filetype detection.
    vim.wo[win].foldenable = false
    pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
    pcall(vim.api.nvim_win_call, win, function()
      vim.cmd('normal! zz')
    end)
  end
end

--- Preview a file on disk, optionally jumping to `lnum`.
function M.show_file(buf, win, filename, lnum)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local ok, lines = pcall(vim.fn.readfile, filename, '', 2000)
  if not ok or not lines or #lines == 0 then
    lines = { '-- unable to preview: ' .. filename }
  end
  set_lines(buf, lines)
  local ft_ok, ft = pcall(vim.filetype.match, { filename = filename })
  vim.bo[buf].filetype = (ft_ok and ft) or ''
  focus_line(win, buf, lnum or 1, #lines)
end

--- Preview the live contents of `src_bufnr` (used for in-buffer search, so
--- the preview reflects unsaved edits too).
function M.show_buffer(buf, win, src_bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_valid(src_bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(src_bufnr, 0, -1, false)
  set_lines(buf, lines)
  vim.bo[buf].filetype = vim.bo[src_bufnr].filetype
  focus_line(win, buf, lnum or 1, #lines)
end

--- Blank the preview pane (e.g. when there are no results).
function M.clear(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  set_lines(buf, {})
  vim.bo[buf].filetype = ''
  vim.api.nvim_buf_clear_namespace(buf, line_ns, 0, -1)
end

return M

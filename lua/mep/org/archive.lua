--- Move a subtree out of the current file and into an archive file,
--- recording where/when it came from.
local outline = require('mep.org.outline')

local M = {}

--- Default archive path for `bufnr`: alongside the original file, named
--- `<basename-without-extension>_archive.org` (`notes.org` ->
--- `notes_archive.org`). Deliberately not real Emacs org-mode's actual
--- default (`%s_archive` appended to the *whole* filename including its
--- extension, producing `notes.org_archive`) — that convention is a
--- common point of confusion even among org users, and there's no
--- compatibility reason to replicate it here. Falls back to
--- `archive.org` in the cwd for an unnamed/scratch buffer.
function M.default_archive_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return vim.fn.getcwd() .. '/archive.org'
  end
  local dir = vim.fn.fnamemodify(name, ':h')
  local base = vim.fn.fnamemodify(name, ':t:r')
  return dir .. '/' .. base .. '_archive.org'
end

--- Move the subtree at `lnum` out of `bufnr` and append it to
--- `archive_path` (default: `default_archive_path(bufnr)`), tagging it
--- with an `ARCHIVE_TIME`/`ARCHIVE_FILE` properties drawer recording
--- where and when. Note: this always inserts a *new* properties drawer,
--- so a headline that already has one will end up with two — property
--- drawer parsing isn't implemented yet (see ORGMODE_ROADMAP.md phase 7);
--- revisit this once it is, to extend an existing drawer instead.
--- Returns the archive file path, or nil if `lnum` isn't inside a
--- headline.
function M.archive_subtree(bufnr, lnum, archive_path)
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end
  archive_path = archive_path or M.default_archive_path(bufnr)

  local stop = outline.subtree_end(bufnr, at)
  local block = vim.api.nvim_buf_get_lines(bufnr, at - 1, stop, false)

  local with_property = {
    block[1],
    ':PROPERTIES:',
    ':ARCHIVE_TIME: ' .. os.date('[%Y-%m-%d %a %H:%M]'),
    ':ARCHIVE_FILE: ' .. vim.api.nvim_buf_get_name(bufnr),
    ':END:',
  }
  for i = 2, #block do
    with_property[#with_property + 1] = block[i]
  end

  local existing = {}
  if vim.fn.filereadable(archive_path) == 1 then
    existing = vim.fn.readfile(archive_path)
  end
  vim.list_extend(existing, with_property)
  vim.fn.mkdir(vim.fn.fnamemodify(archive_path, ':h'), 'p')
  vim.fn.writefile(existing, archive_path)

  vim.api.nvim_buf_set_lines(bufnr, at - 1, stop, false, {})

  return archive_path
end

return M

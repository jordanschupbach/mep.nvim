--- External doc lookup: pure link construction (no in-editor scraping/
--- fetching — the actual page load happens in the browser `vim.ui.open`
--- hands the URL to), via `mep.url.open`, the same "hand a URL to the
--- system opener" path `mep.url`'s own `gx` uses.
local url = require('mep.url')
local templates = require('mep.docs.templates')
local config = require('mep.docs.config')

local M = {}

--- devdocs.io's own instant-search deep link (`#q=...`) for `word`,
--- biased toward `filetype`'s doc set via `mep.docs.templates.doc_hints`
--- (falling back to `config.options.doc_hints`'s own override, then to
--- an unscoped search of just `word` if neither has an entry).
function M.url_for(word, filetype)
  local hint = config.options.doc_hints[filetype] or templates.doc_hints[filetype]
  local query = hint and (hint .. ' ' .. word) or word
  return 'https://devdocs.io/#q=' .. vim.uri_encode(query)
end

--- Open external documentation for the word under the cursor in `win`
--- (`bufnr` is `win`'s buffer). A no-op (with a notification) if there's
--- no word under the cursor.
function M.lookup(bufnr, win)
  -- vim.fn.expand('<cword>') raises (E348) rather than returning '' when
  -- the line has no word-character run at all (e.g. a blank line) —
  -- pcall turns that into the same "nothing under cursor" outcome as an
  -- empty result.
  local ok, word = pcall(vim.api.nvim_win_call, win, function()
    return vim.fn.expand('<cword>')
  end)
  if not ok or not word or word == '' then
    vim.notify('mep.docs: no word under cursor', vim.log.levels.WARN)
    return
  end
  local filetype = vim.bo[bufnr].filetype
  url.open(M.url_for(word, filetype))
end

return M

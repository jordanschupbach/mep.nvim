--- Detect and open URLs in any buffer — `gx`, matching (and gracefully
--- degrading below) Neovim's own built-in default keymap of the same
--- name, plus `gX` (`mep.picker`-backed: list every URL in the buffer,
--- open whichever one you pick) on top. Pure line-pattern parsing
--- (`find`/`find_at_col` mirror `mep.org.link`'s own shape — the same
--- "no dedicated grammar node for this, plain patterns work fine"
--- reasoning applies here too), no tree-sitter/filetype dependency —
--- works in any buffer, unlike `mep.org.link` which only ever looks at
--- `[[...]]`-bracketed org links.
local config = require('mep.url.config')

local M = {}

local URL_PATTERN = "%a[%w+.-]*://[^%s<>\"'%(%)%[%]]+"
local MAILTO_PATTERN = "mailto:[^%s<>\"'%(%)%[%]]+"
local TRAILING_PUNCT = "['\".,;:!?]+$"

--- Find the first URL in `line` at or after byte index `init` (default
--- 1). Returns `start_col, end_col` (1-based, inclusive) and the URL
--- text, or nil if there isn't one. Trailing sentence punctuation
--- (`.,;:!?'"`) right after the match is trimmed off — "see
--- https://x.com." shouldn't pull the period in, and "(https://x.com)"/
--- "[text](https://x.com)" shouldn't pull in the closing paren either
--- (already excluded from the match itself, not trimmed after the
--- fact — parens/brackets/quotes/angle-brackets never count as URL
--- characters at all here).
function M.find(line, init)
  init = init or 1
  local s1, e1 = line:find(URL_PATTERN, init)
  local s2, e2 = line:find(MAILTO_PATTERN, init)
  local s, e
  if s1 and (not s2 or s1 <= s2) then
    s, e = s1, e1
  elseif s2 then
    s, e = s2, e2
  else
    return nil
  end
  local text = line:sub(s, e):gsub(TRAILING_PUNCT, '')
  return s, s + #text - 1, text
end

--- Find the URL in `line` that contains 0-based column `col` (Neovim
--- cursor convention), or nil.
function M.find_at_col(line, col)
  local init = 1
  while true do
    local s, e, url = M.find(line, init)
    if not s then
      return nil
    end
    if col >= s - 1 and col < e then
      return s, e, url
    end
    if s - 1 > col then
      return nil
    end
    init = e + 1
  end
end

--- Every URL in `bufnr`: a list of `{ lnum, col, url }` (1-based line,
--- 1-based start column), in document order.
function M.find_all(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  for lnum, line in ipairs(lines) do
    local init = 1
    while true do
      local s, e, url = M.find(line, init)
      if not s then
        break
      end
      out[#out + 1] = { lnum = lnum, col = s, url = url }
      init = e + 1
    end
  end
  return out
end

--- Open `url` with the system opener (`vim.ui.open`, Neovim >= 0.10).
--- Returns true on success, false (with a notification) if `vim.ui.open`
--- isn't available.
function M.open(url)
  if vim.ui.open then
    vim.ui.open(url)
    return true
  end
  vim.notify('mep.url: vim.ui.open unavailable (needs Neovim 0.10+); cannot open ' .. url, vim.log.levels.WARN)
  return false
end

--- Open the URL under the cursor in `win` (`bufnr`'s line the cursor is
--- on). Returns false (with a notification) if there's no URL under the
--- cursor.
function M.open_at_cursor(bufnr, win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local lnum, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local _, _, url = M.find_at_col(line, col)
  if not url then
    vim.notify('mep.url: no URL under cursor', vim.log.levels.WARN)
    return false
  end
  return M.open(url)
end

--- Open a `mep.picker` over every URL in `bufnr`, opening whichever one
--- you pick. A no-op (with a notification) if the buffer has none.
function M.pick(bufnr)
  local urls = M.find_all(bufnr)
  if #urls == 0 then
    vim.notify('mep.url: no URLs in this buffer', vim.log.levels.INFO)
    return
  end
  require('mep.picker').start({
    prompt_title = 'Open URL',
    items = urls,
    entry_to_string = function(item)
      return string.format('%4d: %s', item.lnum, item.url)
    end,
    on_select = function(item)
      M.open(item.url)
    end,
  })
end

--- Configure mep.url: binds `keymaps.open`/`keymaps.pick` globally (not
--- buffer/filetype-scoped — URLs are relevant in any buffer, unlike
--- e.g. mep.org's own keymaps) — see mep.url.config.defaults.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.open) do
    vim.keymap.set('n', lhs, function()
      M.open_at_cursor(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
    end, { desc = 'mep.url: open URL under cursor' })
  end
  for _, lhs in ipairs(options.keymaps.pick) do
    vim.keymap.set('n', lhs, function()
      M.pick(vim.api.nvim_get_current_buf())
    end, { desc = 'mep.url: pick a URL in this buffer to open' })
  end
  return options
end

return M

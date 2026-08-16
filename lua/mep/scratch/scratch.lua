--- Aggregator and controller for mep's scratch-buffer library: a single
--- persistent, throwaway notepad buffer (unlike `:enew`, whose buffer
--- has no name and — with the default `'hidden'` — can be wiped the
--- moment you switch away from it depending on your own options). Not a
--- floating panel like mep.picker/mep.filetree: it's shown as the
--- current buffer in whatever window you called `open()` from, so it
--- behaves exactly like any other buffer (split it, close it, switch
--- away and back — normal Neovim buffer semantics throughout).
local config = require('mep.scratch.config')

local M = {}

local bufnr = nil

--- Configure the scratch library. See mep.scratch.config.defaults for
--- name/filetype. Works with sensible defaults even if this is never
--- called.
function M.setup(opts)
  return config.setup(opts)
end

--- Open the scratch buffer in the current window, creating it (once per
--- session, or since the last `reset()`) the first time this is called.
--- `buftype=nofile`/`swapfile=false` so it never touches disk;
--- `bufhidden=hide` (not `:enew`'s `'wipe'`-if-`'hidden'`-is-off
--- behavior) so its content survives switching away and back.
function M.open()
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'hide'
    vim.bo[bufnr].swapfile = false
    if config.options.filetype ~= '' then
      vim.bo[bufnr].filetype = config.options.filetype
    end
    pcall(vim.api.nvim_buf_set_name, bufnr, config.options.name)
  end
  vim.api.nvim_set_current_buf(bufnr)
end

--- Discard the current scratch buffer (wiping it if still loaded) so the
--- next `open()` starts over with a brand new, empty one.
function M.reset()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  bufnr = nil
end

return M

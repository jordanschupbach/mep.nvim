--- Aggregator for mep's play-button library: run the current file
--- through `mep.org.babel`'s own per-language interpreter/compiler
--- resolution (`mep.run.runner`), output going to a real `:terminal`
--- split (`mep.run.terminal`, `mep.project`'s own terminal-split usage
--- as precedent). `M.widget()` is a `mep.chrome`-widget-shaped table
--- (`{ text, on_click }`) — the two libraries are independent, composed
--- only via config, like every other pairing in this project; plug it
--- into `require('mep.chrome').setup({ winbar = { widgets = {
--- require('mep.run').widget() } } })` (or `statusline`'s own
--- `widgets`) for a clickable ▶ button.
local config = require('mep.run.config')
local runner = require('mep.run.runner')
local terminal = require('mep.run.terminal')

local M = {}
M.runner = runner
M.terminal = terminal

--- Run `bufnr` (default the current buffer) through its own filetype's
--- interpreter/compiler, in a new `:terminal` split. Notifies (no-op)
--- if the filetype has no curated run command, or its interpreter/
--- compiler isn't on PATH, or the buffer has no file at all.
function M.run_current_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cmd, err = runner.command(bufnr)
  if not cmd then
    vim.notify(err, vim.log.levels.WARN)
    return
  end
  terminal.open(cmd)
end

--- A `mep.chrome`-widget-shaped table for a clickable play button — see
--- this module's own header comment.
function M.widget()
  return {
    text = ' ▶ ',
    on_click = function()
      M.run_current_file()
    end,
  }
end

--- Configure mep.run: extra/override `filetype_to_babel`,
--- `terminal_height_ratio`, and `keymaps.run` (global — see
--- mep.run.config.defaults). Works with sensible defaults even if this
--- is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.run) do
    vim.keymap.set('n', lhs, function()
      M.run_current_file()
    end, { desc = 'mep.run: run the current file' })
  end
  return options
end

return M

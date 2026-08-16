--- Opens a real `:terminal` split running a given argv directly (`vim.
--- fn.jobstart(cmd, { term = true })`, no shell involved unless `cmd`
--- itself is one) — `mep.project`'s own terminal-split usage (`split`
--- below the current window, `splitbelow`/`equalalways` forced for
--- just this one split, sized to `config.options.
--- terminal_height_ratio`) as precedent, adapted to run a specific
--- command instead of an interactive shell.
local config = require('mep.run.config')

local M = {}

--- Split below the current window (sized to `config.options.
--- terminal_height_ratio` of its height) and run `cmd` (a plain argv
--- list) there as a real terminal job. Leaves the terminal focused
--- (freshly opened terminals start in Terminal-Job mode) — same
--- "caller refocuses if it wants to" contract `mep.project`'s own
--- terminal-split helper documents. Returns the new terminal buffer.
function M.open(cmd)
  local total_height = vim.api.nvim_win_get_height(vim.api.nvim_get_current_win())
  local save_splitbelow, save_equalalways = vim.o.splitbelow, vim.o.equalalways
  vim.o.splitbelow = true
  vim.o.equalalways = false
  vim.cmd('split')
  vim.o.splitbelow, vim.o.equalalways = save_splitbelow, save_equalalways

  local terminal_height = math.max(1, math.floor(total_height * config.options.terminal_height_ratio + 0.5))
  vim.cmd('resize ' .. terminal_height)

  vim.cmd('enew')
  vim.fn.jobstart(cmd, { term = true })
  return vim.api.nvim_get_current_buf()
end

return M

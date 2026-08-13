--- Aggregator and controller for mep's dashboard library: shows content
--- (by default, a recreation of Neovim's own intro screen — see
--- content.lua) in place of the initial empty buffer at startup.
local config = require('mep.dashboard.config')
local content = require('mep.dashboard.content')
local ui = require('mep.dashboard.ui')

local M = {}

local stdin_read = false
local autocmd_group = nil

--- Configure the dashboard library and, unless `auto_open = false`,
--- register the startup autocmds. See mep.dashboard.config.defaults.
function M.setup(opts)
  local options = config.setup(opts)
  if options.auto_open then
    M.enable_auto_open()
  else
    M.disable_auto_open()
  end
  return options
end

--- Render the dashboard into the current window/buffer, replacing its
--- content. Used both for auto-open at startup and for `:MepDashboard`.
--- This is a real, reused window (not a throwaway panel), so `ui.
--- prepare_window`'s gutter/number/eob suppression gets undone
--- automatically the moment `buf` is no longer showing here (`bufhidden
--- = 'wipe'`, from `ui.prepare_buffer`, fires `BufWipeout` as soon as
--- something replaces it — e.g. opening a real file over the
--- dashboard) — otherwise those overrides would silently outlive the
--- dashboard itself in whatever window showed it.
function M.open()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  ui.prepare_buffer(buf)
  local saved_win_opts = ui.prepare_window(win)
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      ui.restore_window(win, saved_win_opts)
    end,
  })
  local lines = content.resolve(config.options.content)
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  ui.render(buf, ui.center(lines, width, height))
end

--- Whether the current editor state looks like a fresh, untouched start
--- (no file arguments, a single empty unnamed unmodified buffer, one
--- window, and no piped stdin) — the same conditions Neovim's own intro
--- screen uses to decide whether to show itself.
function M.should_auto_open()
  if stdin_read then
    return false
  end
  if vim.fn.argc() > 0 then
    return false
  end
  if #vim.api.nvim_list_wins() > 1 then
    return false
  end
  if vim.api.nvim_buf_get_name(0) ~= '' then
    return false
  end
  if vim.bo.filetype ~= '' then
    return false
  end
  if vim.bo.modified then
    return false
  end
  if vim.api.nvim_buf_line_count(0) > 1 then
    return false
  end
  local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  if first_line and first_line ~= '' then
    return false
  end
  return true
end

--- Register the VimEnter (and a StdinReadPre guard) autocmds that call
--- `open()` automatically when `should_auto_open()` holds. Called by
--- `setup()` unless `auto_open = false`; exposed separately in case you
--- want to turn it on/off after the fact.
function M.enable_auto_open()
  M.disable_auto_open()
  autocmd_group = vim.api.nvim_create_augroup('MepDashboard', { clear = true })
  vim.api.nvim_create_autocmd('StdinReadPre', {
    group = autocmd_group,
    callback = function()
      stdin_read = true
    end,
  })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = autocmd_group,
    callback = function()
      if M.should_auto_open() then
        M.open()
      end
    end,
  })
end

function M.disable_auto_open()
  if autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
    autocmd_group = nil
  end
end

--- Forget cached auto-open state (the stdin-read flag) and stop
--- listening for the startup autocmds. Mainly useful for tests, or if
--- you want a clean slate before calling `enable_auto_open()` again.
function M.reset()
  M.disable_auto_open()
  stdin_read = false
end

return M

--- Aggregator for mep's zen mode: `:MepZenToggle` / `require('mep.zen').
--- toggle()` hides `mep.activitybar`, closes `mep.filetree`/`mep.
--- symbols` if open, turns off the gutter (`mep.zen.gutter`) and `mep.
--- chrome`'s statusline/winbar/statuscolumn, and centers the current
--- window's buffer (`mep.zen.layout`) — restoring the exact prior state
--- on exit. Every piece is individually toggleable via `config.
--- options.hide` (same "everything independently disableable"
--- convention `mep.sanity` uses).
---
--- Each of `mep.activitybar`/`mep.filetree`/`mep.symbols`/`mep.chrome`
--- is a soft, optional dependency (`pcall`'d `require`s) — using zen
--- mode without any of them installed/loaded just skips that piece.
local config = require('mep.zen.config')
local gutter = require('mep.zen.gutter')
local layout = require('mep.zen.layout')

local M = {}
M.gutter = gutter
M.layout = layout

-- { win, saved_gutter, padding, activitybar_was_open, filetree_was_open,
--   symbols_was_open, chrome_was = { statusline, winbar, statuscolumn } }
-- — nil when zen mode isn't active.
local state = nil

--- Whether zen mode is currently active.
function M.is_active()
  return state ~= nil
end

local function close_if_open(module_name, is_open_fn_name, close_fn_name)
  local ok, mod = pcall(require, module_name)
  if not ok then
    return false
  end
  local is_open = mod[is_open_fn_name]()
  if is_open then
    mod[close_fn_name]()
  end
  return is_open
end

--- Enter zen mode for the current window. A no-op if already active.
function M.enable()
  if state then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local hide = config.options.hide

  local activitybar_was_open = false
  if hide.activitybar then
    local ok, activitybar = pcall(require, 'mep.activitybar')
    if ok then
      local bar = activitybar.bar()
      activitybar_was_open = bar:is_open()
      if activitybar_was_open then
        bar:close()
      end
    end
  end

  local filetree_was_open = false
  if hide.filetree then
    filetree_was_open = close_if_open('mep.filetree', 'is_open', 'close')
  end

  local symbols_was_open = false
  if hide.symbols then
    symbols_was_open = close_if_open('mep.symbols', 'is_open', 'close')
  end

  local saved_gutter = nil
  if hide.gutter then
    saved_gutter = gutter.suppress(win)
  end

  local chrome_was = nil
  if hide.chrome then
    local ok, chrome_config = pcall(require, 'mep.chrome.config')
    if ok then
      chrome_was = {
        statusline = chrome_config.options.statusline.enable,
        winbar = chrome_config.options.winbar.enable,
        statuscolumn = chrome_config.options.statuscolumn.enable,
      }
      local chrome = require('mep.chrome')
      chrome.statusline.disable()
      chrome.winbar.disable()
      chrome.statuscolumn.disable()
    end
  end

  local padding = layout.center(win, config.options.width)

  state = {
    win = win,
    saved_gutter = saved_gutter,
    padding = padding,
    activitybar_was_open = activitybar_was_open,
    filetree_was_open = filetree_was_open,
    symbols_was_open = symbols_was_open,
    chrome_was = chrome_was,
  }
end

--- Exit zen mode, restoring the exact prior state. A no-op if not
--- currently active.
function M.disable()
  if not state then
    return
  end
  local st = state
  state = nil

  layout.uncenter(st.padding)

  if st.saved_gutter then
    gutter.restore(st.win, st.saved_gutter)
  end

  if st.chrome_was then
    local ok, chrome = pcall(require, 'mep.chrome')
    if ok then
      if st.chrome_was.statusline then
        chrome.statusline.enable()
      end
      if st.chrome_was.winbar then
        chrome.winbar.enable()
      end
      if st.chrome_was.statuscolumn then
        chrome.statuscolumn.enable()
      end
    end
  end

  if st.activitybar_was_open then
    local ok, activitybar = pcall(require, 'mep.activitybar')
    if ok then
      activitybar.bar():open()
    end
  end
  if st.filetree_was_open then
    pcall(function()
      require('mep.filetree').open()
    end)
  end
  if st.symbols_was_open then
    pcall(function()
      require('mep.symbols').open()
    end)
  end
end

--- Enter/exit zen mode.
function M.toggle()
  if M.is_active() then
    M.disable()
  else
    M.enable()
  end
end

--- Configure mep.zen: `width`, `hide`, `keymaps` (see mep.zen.config.
--- defaults). Works with sensible defaults even if this is never
--- called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.toggle) do
    vim.keymap.set('n', lhs, M.toggle, { desc = 'mep.zen: toggle zen mode' })
  end
  return options
end

--- Test/dev-only: forget any active zen session without restoring
--- anything (does not close padding windows or reapply saved
--- options/reopen panels) — for state hygiene between specs, not a
--- real exit.
function M._reset()
  state = nil
end

return M

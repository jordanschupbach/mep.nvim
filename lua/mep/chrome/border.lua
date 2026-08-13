--- Colors the active window's edges on focus change, natively —
--- winhighlight overrides on real window options, no floating overlay.
--- This is deliberately NOT a floating-window overlay: an overlay
--- would either block the real statusline/winbar content underneath it
--- or need to duplicate it, whereas native per-window highlight
--- overrides stay fully compatible with a real, content-bearing
--- statusline/winbar (mep.chrome's own, or none at all — see the
--- `border` section of `mep.chrome.config`'s own header for why this
--- was the deciding factor).
---
--- Each side maps to a real Neovim highlight seam:
---   right  -> the active window's own 'WinSeparator' (`:help
---             winhighlight`: a vertical separator's highlighting is
---             owned by the window to *its* left — i.e. by whichever
---             window is on that side, so "my right edge" is always
---             my own WinSeparator)
---   left   -> by the same rule, the separator to *my* left is owned
---             by my left neighbor, not by me — so this recolors the
---             neighbor's own WinSeparator, found via `wincmd h` run
---             against a temporarily-current window (no other API
---             gives you "the window to the left of window N" without
---             actually focusing it first)
---   top    -> the active window's own 'WinBar'/'WinBarNC' (only
---             visible if that window actually shows a winbar)
---   bottom -> the active window's own 'StatusLine'/'StatusLineNC'
---             (only visible if it shows its own statusline — not
---             merged into one global bar via `laststatus=3`)
--- A window at the screen edge (no left/right neighbor, or `laststatus`
--- hides individual statuslines) simply has nothing there to recolor —
--- an inherent limitation of any terminal-based split layout, not
--- something a float could meaningfully fix either.
local config = require('mep.chrome.config')

local M = {}

local GROUP = 'MepChromeBorderActive'

-- winid -> the list of winhighlight keys *this module* last set GROUP on
-- for that window (nil if none). Deliberately not a snapshot of the
-- window's whole former 'winhighlight' string — Neovim copies window-
-- local options (including 'winhighlight') from the window a `:split`/
-- `:vsplit` was run against into the newly created window, so a just-
-- split window can start out already carrying a *previous* apply()'s
-- GROUP entries verbatim, before this module has touched it at all. If
-- `restore()` "reverted" to a per-window snapshot taken at that moment,
-- it would snapshot (and later restore right back to) that inherited
-- colored value instead of a real blank baseline, permanently baking
-- the border into every window ever split from an active one — confirmed
-- the hard way, splitting repeatedly left every pane colored instead of
-- just the current one. Tracking *which keys are ours* and deleting
-- exactly those from whatever 'winhighlight' currently is sidesteps the
-- whole problem: it's independent of how the window came to exist, and
-- idempotent regardless of order.
local active_keys = {}

local function parse(winhighlight)
  local map = {}
  if winhighlight and winhighlight ~= '' then
    for pair in winhighlight:gmatch('[^,]+') do
      local key, value = pair:match('^(.-):(.+)$')
      if key then
        map[key] = value
      end
    end
  end
  return map
end

local function stringify(map)
  local parts = {}
  for key, value in pairs(map) do
    parts[#parts + 1] = key .. ':' .. value
  end
  table.sort(parts)
  return table.concat(parts, ',')
end

local function set_override(win, keys)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local map = parse(vim.api.nvim_get_option_value('winhighlight', { win = win }))
  for _, key in ipairs(keys) do
    map[key] = GROUP
  end
  vim.api.nvim_set_option_value('winhighlight', stringify(map), { win = win })
  active_keys[win] = keys
end

local function restore(win)
  local keys = active_keys[win]
  if keys and vim.api.nvim_win_is_valid(win) then
    local map = parse(vim.api.nvim_get_option_value('winhighlight', { win = win }))
    for _, key in ipairs(keys) do
      if map[key] == GROUP then
        map[key] = nil
      end
    end
    vim.api.nvim_set_option_value('winhighlight', stringify(map), { win = win })
  end
  active_keys[win] = nil
end

local function clear_all()
  local wins = {}
  for win in pairs(active_keys) do
    wins[#wins + 1] = win
  end
  for _, win in ipairs(wins) do
    restore(win)
  end
end

local ALL_KEYS = { 'WinSeparator', 'WinBar', 'WinBarNC', 'StatusLine', 'StatusLineNC' }

local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ''
end

--- Strip any `GROUP` entries from `win`'s *current* 'winhighlight' —
--- for a window this module never `set_override()`d (so `active_keys`
--- has nothing to `restore()`), the only way it could be carrying our
--- color at all is the same option-inheritance quirk `active_keys`'
--- own header comment describes: Neovim copies 'winhighlight' from the
--- current window into ANY newly created one, floats included (`mep.
--- sidebar`'s own float windows, `nvim_open_win(..., true, ...)`,
--- enter what they create — ordinarily that means a real WinEnter
--- fires and `apply()` below reaches this same function for it, once,
--- right after creation; `sweep_floats` exists for the one startup-time
--- case that WinEnter never fires for at all). A float can never
--- legitimately carry our color (this module only ever borders real
--- windows), so any presence of it here is always leftover residue,
--- safe to strip unconditionally.
local function strip_group(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local map = parse(vim.api.nvim_get_option_value('winhighlight', { win = win }))
  local changed = false
  for _, key in ipairs(ALL_KEYS) do
    if map[key] == GROUP then
      map[key] = nil
      changed = true
    end
  end
  if changed then
    vim.api.nvim_set_option_value('winhighlight', stringify(map), { win = win })
  end
end

--- `nvim_set_current_win` (unlike `wincmd`) has no `noautocmd` form of
--- its own, and this function needs to call it twice (into `win`, then
--- back to `original`) purely to probe position — genuinely firing
--- WinEnter/WinLeave for either hop would be a real, externally-visible
--- focus change nothing asked for, and (now that `apply`'s own autocmd
--- below is `nested = true`, so it no longer *ignores* a WinEnter
--- triggered while another autocmd is still running — see that autocmd
--- definition for why) would recursively re-enter `apply()` for the
--- same window this call is already inside of, indefinitely. Silencing
--- every window/buffer-focus event around the whole probe (not just the
--- `wincmd` hop, already `noautocmd` on its own) rules that out
--- entirely, regardless of what else is listening.
local function left_neighbor(win)
  local original = vim.api.nvim_get_current_win()
  local saved_eventignore = vim.o.eventignore
  vim.o.eventignore = 'WinEnter,WinLeave,WinNew,BufEnter,BufLeave'
  local ok, result = pcall(function()
    vim.api.nvim_set_current_win(win)
    vim.cmd('wincmd h')
    local r = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(original) then
      vim.api.nvim_set_current_win(original)
    end
    return r
  end)
  vim.o.eventignore = saved_eventignore
  if not ok or result == win then
    return nil
  end
  return result
end

--- Every currently open float that's carrying a stray `GROUP` entry
--- (see `strip_group`'s own header for how it gets there) gets it
--- cleaned. The one case `apply()`'s own per-window cleanup can never
--- reach on its own: a float opened *from* a `VimEnter` autocmd (`mep.
--- activitybar`'s own auto-open bar, `mep.dashboard`'s own — both
--- register one) — Neovim suppresses every other autocmd, WinEnter/
--- WinNew included, `nested = true` or not, for the whole duration of
--- VimEnter's own dispatch (confirmed the hard way: a `nvim_open_win(
--- ..., true, ...)` that demonstrably moves focus to the window it just
--- created still never fires WinEnter *or* WinNew for it mid-VimEnter,
--- while the exact same call fires both immediately outside one). Only
--- called from the `VimEnter` branch below, wrapped in `vim.schedule`
--- so it runs after that suppression has lifted — by which point every
--- *other* VimEnter listener (including whichever one just opened the
--- float in the first place) has already run too, so this reliably
--- catches it regardless of listener registration order.
local function sweep_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_float(win) then
      strip_group(win)
    end
  end
end

local function apply(win)
  clear_all()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if is_float(win) then
    strip_group(win)
    return
  end

  local sides = config.options.border.sides
  local keys = {}
  if sides.right then
    keys[#keys + 1] = 'WinSeparator'
  end
  if sides.top then
    vim.list_extend(keys, { 'WinBar', 'WinBarNC' })
  end
  if sides.bottom then
    vim.list_extend(keys, { 'StatusLine', 'StatusLineNC' })
  end
  if #keys > 0 then
    set_override(win, keys)
  end

  if sides.left then
    local neighbor = left_neighbor(win)
    if neighbor then
      set_override(neighbor, { 'WinSeparator' })
    end
  end
end

local enabled = false
local augroup

function M.enable()
  if enabled then
    return
  end
  enabled = true
  augroup = vim.api.nvim_create_augroup('MepChromeBorder', { clear = true })
  -- `nested = true`: a WinEnter genuinely caused by something *else's*
  -- own autocmd (e.g. `mep.sidebar`'s float windows enter themselves on
  -- open) would otherwise never reach this callback at all (`:help
  -- autocmd-nested` — Vim doesn't fire further autocmds of a kind
  -- that's already being processed, by default, specifically to stop
  -- careless autocmds from looping forever). Doesn't, on its own, cover
  -- every such case — see `sweep_floats`'s own header for the one
  -- Neovim's VimEnter dispatch blocks even with `nested = true` — but
  -- still correct and worth having for ordinary (post-startup) nested
  -- opens. Safe from the runaway-nesting `nested` is normally guarding
  -- against specifically because `left_neighbor` (this module's only
  -- source of *self*-triggered focus changes) silences its own probe
  -- with `eventignore`, so nothing left in this module can recursively
  -- re-trigger this same callback.
  vim.api.nvim_create_autocmd({ 'WinEnter', 'VimEnter' }, {
    group = augroup,
    nested = true,
    callback = function(args)
      apply(vim.api.nvim_get_current_win())
      if args.event == 'VimEnter' then
        vim.schedule(sweep_floats)
      end
    end,
  })
  apply(vim.api.nvim_get_current_win())
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  clear_all()
  active_keys = {}
end

function M._reset()
  M.disable()
end

return M

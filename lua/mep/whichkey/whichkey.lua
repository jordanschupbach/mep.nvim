--- Aggregator for mep's which-key library: a floating popup that shows
--- what's bound under a prefix key (`<leader>` by default) and its
--- description, discovered by introspecting real keymaps
--- (`mep.whichkey.registry`) rather than requiring a separate
--- registration step — any `vim.keymap.set` call anywhere (this
--- project's own libraries, or a user's own config) shows up
--- automatically as long as it has a `desc`.
---
--- The popup itself follows `mep.org.tags.select_interactive`'s own
--- pattern (a scratch buffer, one keymap per option, `<Esc>`/`q` to
--- dismiss) rather than a blocking `getcharstr()` read loop — simpler to
--- reason about and test, and consistent with how this project already
--- builds a "pick one of a few options" popup elsewhere. Where it
--- appears is `config.position` (see mep.whichkey.config.defaults):
--- `'bottom'` (default, real which-key.nvim's own default look — spans
--- the full editor width, entries laid out in a column-major grid),
--- `'top'`, or `'cursor'` (a compact single column, this library's
--- original v1 look).
---
--- **Scope note**: no debounce/typeahead-skip like real which-key.nvim's
--- optional delay (type the whole sequence fast enough and the popup
--- never appears) — the popup always shows immediately once a trigger
--- fires. Kept simple, and there's nothing to skip *to* on the very
--- first key anyway (a trigger like `<leader>` isn't bound to anything
--- else).
local config = require('mep.whichkey.config')
local registry = require('mep.whichkey.registry')

local M = {}
M.registry = registry

--- `human` (e.g. `'<leader>'`, `'f'`) as raw keycode bytes — the
--- representation `mep.whichkey.registry` works in throughout. See
--- registry.lua's header comment for why raw bytes, not `<...>`
--- notation, are the shared representation.
local function to_raw(human)
  return vim.api.nvim_replace_termcodes(human, true, true, true)
end
M.to_raw = to_raw

--- Run keymap dict `m` (as from `mep.whichkey.registry.all`) exactly as
--- Neovim itself would if its `lhs` had been typed directly: call its
--- `callback` if it has one (every mapping this project's own libraries
--- define), otherwise feed its string `rhs` back through
--- `nvim_feedkeys` (`noremap`-aware); an `expr` mapping's `rhs`/
--- `callback` return value is evaluated first and *that* result is what
--- gets fed.
function M.execute(m)
  if m.expr == 1 then
    local result = m.callback and m.callback() or vim.fn.eval(m.rhs)
    if type(result) == 'string' and result ~= '' then
      local flag = (m.noremap == 1) and 'ni' or 'mi'
      vim.api.nvim_feedkeys(to_raw(result), flag, false)
    end
    return
  end
  if m.callback then
    m.callback()
    return
  end
  if m.rhs and m.rhs ~= '' then
    local flag = (m.noremap == 1) and 'ni' or 'mi'
    vim.api.nvim_feedkeys(to_raw(m.rhs), flag, false)
  end
end

--- Render `groups` (as from `mep.whichkey.registry.compute_groups`) as
--- a single left-aligned column, one "key  desc" per line — used for
--- `position = 'cursor'`.
local function render_column(groups)
  local key_width = 4
  for _, g in ipairs(groups) do
    key_width = math.max(key_width, vim.fn.strdisplaywidth(g.key))
  end
  local lines = {}
  for _, g in ipairs(groups) do
    lines[#lines + 1] = g.key .. string.rep(' ', key_width - vim.fn.strdisplaywidth(g.key) + 2) .. g.desc
  end
  return lines
end

--- Render `groups` into a column-major grid (fill down a column before
--- starting the next — real which-key.nvim's own convention) at most
--- `available_width` display cells wide — used for `position =
--- 'bottom'`/`'top'` to make use of the full editor width rather than
--- one cramped column. Returns the output lines.
local function render_grid(groups, available_width)
  local key_width = 4
  for _, g in ipairs(groups) do
    key_width = math.max(key_width, vim.fn.strdisplaywidth(g.key))
  end
  local entries = {}
  local entry_width = 0
  for _, g in ipairs(groups) do
    local text = g.key .. string.rep(' ', key_width - vim.fn.strdisplaywidth(g.key) + 2) .. g.desc
    entries[#entries + 1] = text
    entry_width = math.max(entry_width, vim.fn.strdisplaywidth(text))
  end

  local col_width = entry_width + 3
  local columns = math.max(1, math.min(#entries, math.floor(available_width / col_width)))
  local rows = math.ceil(#entries / columns)

  local lines = {}
  for r = 1, rows do
    local parts = {}
    for c = 1, columns do
      local idx = (c - 1) * rows + r
      if entries[idx] then
        local text = entries[idx]
        if c < columns then
          text = text .. string.rep(' ', col_width - vim.fn.strdisplaywidth(text))
        end
        parts[#parts + 1] = text
      end
    end
    lines[#lines + 1] = table.concat(parts)
  end
  return lines
end
M.render_grid = render_grid

--- The popup content (output lines) and `nvim_open_win` config for
--- showing `groups`, according to `config.options.position`/`border`:
--- `'cursor'` places a compact single column just under the cursor
--- (this library's original v1 look); `'bottom'`/`'top'` place a grid
--- spanning the full editor width, anchored just above the command line
--- or at row 0 respectively (real which-key.nvim's own default look).
--- A non-`'none'` border reserves 1 cell of padding on every side, so
--- the window's content area is inset accordingly to keep the *outer*
--- edge flush with the requested position.
function M.layout(groups)
  local border = config.options.border
  local pad = (not border or border == 'none') and 0 or 2

  if config.options.position ~= 'bottom' and config.options.position ~= 'top' then
    local lines = render_column(groups)
    local width = 10
    for _, l in ipairs(lines) do
      width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
    end
    return lines, {
      relative = 'cursor',
      row = 1,
      col = 0,
      width = width,
      height = #lines,
      style = 'minimal',
      border = border,
    }
  end

  local width = vim.o.columns - pad
  local lines = render_grid(groups, width)
  local row = (config.options.position == 'top') and 0 or math.max(0, vim.o.lines - vim.o.cmdheight - #lines - pad)
  return lines, {
    relative = 'editor',
    row = row,
    col = 0,
    width = width,
    height = #lines,
    style = 'minimal',
    border = border,
  }
end

--- Show what's bound under `prefix_raw` (raw keycode bytes) for
--- `mode`/`bufnr`: a floating popup listing each next key and its
--- description if there's more than one way forward, executing directly
--- with no popup at all for a single unambiguous leaf, or a
--- notification if nothing is bound under `prefix_raw` at all. Pressing
--- a listed key either runs its mapping (a leaf) or descends into
--- another popup for the next level (a group — real which-key's own
--- "submenu" concept); `<Esc>`/`q` dismiss without doing anything.
function M.descend(mode, bufnr, prefix_raw)
  local groups, exact = registry.compute_groups(mode, bufnr, prefix_raw)
  if #groups == 0 then
    if exact then
      M.execute(exact)
    else
      vim.notify('mep.whichkey: no mappings under ' .. vim.fn.keytrans(prefix_raw), vim.log.levels.WARN)
    end
    return
  end

  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[popup_buf].bufhidden = 'wipe'
  local lines, win_opts = M.layout(groups)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.bo[popup_buf].modifiable = false

  local popup_win = vim.api.nvim_open_win(popup_buf, true, win_opts)

  local function close()
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
  end

  local map_opts = { buffer = popup_buf, nowait = true, silent = true }
  for _, g in ipairs(groups) do
    vim.keymap.set('n', g.key, function()
      close()
      local new_prefix = prefix_raw .. to_raw(g.key)
      if g.is_group then
        M.descend(mode, bufnr, new_prefix)
      else
        M.execute(g.leaf)
      end
    end, map_opts)
  end
  vim.keymap.set('n', '<Esc>', close, map_opts)
  vim.keymap.set('n', 'q', close, map_opts)
end

--- Trigger the popup for `human_prefix` (e.g. `'<leader>'`) in `mode`
--- (default `'n'`), showing whatever's bound under it in the current
--- buffer.
function M.show(human_prefix, mode)
  M.descend(mode or 'n', 0, to_raw(human_prefix))
end

--- Configure mep.whichkey: `triggers` (default `{'<leader>'}`) become
--- keymaps (in every configured `modes`, default `{'n'}`) that open the
--- popup — see mep.whichkey.config.defaults. Note: if `<leader>` is one
--- of your triggers (the default), call this *after* whatever sets
--- `vim.g.mapleader` (`mep.sanity.setup`, if you use it) — like any
--- `<leader>`-using keymap, Neovim resolves `<leader>` to the current
--- `mapleader` at the point the mapping is *defined*, not when it's
--- pressed.
function M.setup(opts)
  local options = config.setup(opts)
  for _, mode in ipairs(options.modes) do
    for _, trigger in ipairs(options.triggers) do
      vim.keymap.set(mode, trigger, function()
        M.show(trigger, mode)
      end, { desc = 'mep.whichkey: show mappings' })
    end
  end
  return options
end

return M

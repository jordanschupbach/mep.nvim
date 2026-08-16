--- Stacked, auto-dismissing toast popups — the "nvim-notify"-style
--- half of `mep.notify`: one small floating window per notification,
--- anchored in a screen corner (`config.options.position`), colored by
--- level (border highlight + a highlighted icon/header line), stacking
--- away from the corner as more arrive and reflowing instantly whenever
--- one closes (by timeout, eviction, or `M.dismiss_all`) so there's
--- never a gap in the stack. Pure UI — `mep.notify.notify` is the only
--- caller that feeds this real entries; everything here only ever reads
--- `entry.text`/`entry.level`/`entry.title`, never mutates history.
local sidebar_mod = require('mep.sidebar')
local config = require('mep.notify.config')

local uv = vim.uv or vim.loop

local M = {}

-- Newest-first: active[1] is the most recently shown toast, always the
-- one closest to the configured corner — see `reflow`'s own comment for
-- why that ordering matters to the stacking math.
local active = {}

local LEVEL_HL = {
  [vim.log.levels.ERROR] = 'MepNotifyError',
  [vim.log.levels.WARN] = 'MepNotifyWarn',
  [vim.log.levels.INFO] = 'MepNotifyInfo',
  [vim.log.levels.DEBUG] = 'MepNotifyDebug',
  [vim.log.levels.TRACE] = 'MepNotifyDebug',
}

local LEVEL_LABEL = {
  [vim.log.levels.ERROR] = 'Error',
  [vim.log.levels.WARN] = 'Warning',
  [vim.log.levels.INFO] = 'Info',
  [vim.log.levels.DEBUG] = 'Debug',
  [vim.log.levels.TRACE] = 'Trace',
}

--- `('top'|'bottom', 'left'|'right')` from `config.options.position`.
local function corner_parts(position)
  local vert = position:match('^top') and 'top' or 'bottom'
  local horiz = position:match('right$') and 'right' or 'left'
  return vert, horiz
end

--- Greedy word-wrap of `text` (newlines respected as hard breaks) to at
--- most `width` display columns per line.
local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(text, '\n', { plain = true })) do
    if para == '' then
      out[#out + 1] = ''
    else
      local line = ''
      for word in para:gmatch('%S+') do
        local candidate = (line == '' and word or (line .. ' ' .. word))
        if vim.fn.strdisplaywidth(candidate) > width and line ~= '' then
          out[#out + 1] = line
          line = word
        else
          line = candidate
        end
      end
      if line ~= '' then
        out[#out + 1] = line
      end
    end
  end
  if #out == 0 then
    out[1] = ''
  end
  return out
end

--- `(lines, width, hl)` for `entry` — a header line (icon + title, or
--- the level's own plain label when `entry.title` is unset) followed by
--- `entry.text` word-wrapped alongside it, sized between `cfg.min_width`
--- and `cfg.max_width`.
local function build(entry, cfg)
  local icon = cfg.icons[entry.level] or cfg.icons[vim.log.levels.INFO]
  local header = icon .. ' ' .. (entry.title and entry.title ~= '' and entry.title or (LEVEL_LABEL[entry.level] or 'Info'))
  local content_width = cfg.max_width - cfg.padding * 2
  local lines = { header }
  vim.list_extend(lines, wrap(entry.text or '', content_width))

  local longest = 0
  for _, line in ipairs(lines) do
    longest = math.max(longest, vim.fn.strdisplaywidth(line))
  end
  local width = math.max(cfg.min_width, math.min(cfg.max_width, longest + cfg.padding * 2))

  local padded = {}
  for i, line in ipairs(lines) do
    padded[i] = string.rep(' ', cfg.padding) .. line
  end

  return padded, width, LEVEL_HL[entry.level] or LEVEL_HL[vim.log.levels.INFO]
end

local function compute_col(width, horiz, cfg)
  local pad = sidebar_mod.border_pad(cfg.border)
  if horiz == 'right' then
    return math.max(0, vim.o.columns - width - cfg.margin - pad)
  end
  return cfg.margin
end

--- Reposition every currently-active toast so they stack outward from
--- the configured corner with no gap and no overlap — called after any
--- add/remove. `active[1]` (newest) always lands right at the corner;
--- each subsequent entry sits `height + border + spacing` further away
--- from it, in display order.
local function reflow()
  local cfg = config.options
  local vert, horiz = corner_parts(cfg.position)
  local pad = sidebar_mod.border_pad(cfg.border)
  local avail_height = vim.o.lines - vim.o.cmdheight
  local cursor = cfg.margin

  for _, a in ipairs(active) do
    if vim.api.nvim_win_is_valid(a.win) then
      local row
      if vert == 'top' then
        row = cursor
      else
        row = avail_height - cursor - a.height - pad
      end
      pcall(vim.api.nvim_win_set_config, a.win, { relative = 'editor', row = math.max(0, row), col = a.col, width = a.width, height = a.height })
    end
    cursor = cursor + a.height + pad + cfg.spacing
  end
end

--- Close `a` (idempotent — a second call, or one racing a timeout
--- against a manual dismiss, is a no-op), remove it from `active`, and
--- reflow the rest into its place.
local function close_entry(a)
  if not a or a.closed then
    return
  end
  a.closed = true
  if a.timer then
    pcall(function()
      a.timer:stop()
      a.timer:close()
    end)
    a.timer = nil
  end
  if vim.api.nvim_win_is_valid(a.win) then
    pcall(vim.api.nvim_win_close, a.win, true)
  end
  for i, x in ipairs(active) do
    if x == a then
      table.remove(active, i)
      break
    end
  end
  reflow()
end

--- Show `entry` (`{ text, level, title? }`, `mep.notify`'s own entry
--- shape) as a new toast, evicting the oldest currently-visible one
--- first if already at `cfg.max_visible`. `override` (`{ timeout?,
--- max_visible? }`) exists mainly for tests that don't want to wait out
--- real multi-second timeouts — real callers (`mep.notify.notify`)
--- never pass it, relying on `config.options` alone. Returns the new
--- toast's window id.
function M.show(entry, override)
  override = override or {}
  local cfg = config.options

  local max_visible = override.max_visible or cfg.max_visible
  if #active >= max_visible then
    close_entry(active[#active])
  end

  local lines, width, hl = build(entry, cfg)
  local _, horiz = corner_parts(cfg.position)
  local col = compute_col(width, horiz, cfg)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_add_highlight(buf, -1, hl, 0, 0, -1)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 0,
    col = col,
    width = width,
    height = #lines,
    style = 'minimal',
    border = cfg.border,
    focusable = false,
    noautocmd = true,
    zindex = 200,
  })
  vim.wo[win].winhighlight = 'FloatBorder:' .. hl

  local a = { win = win, buf = buf, width = width, height = #lines, col = col, level = entry.level }
  table.insert(active, 1, a)

  local timeout = override.timeout
  if timeout == nil then
    timeout = cfg.timeout[entry.level]
    if timeout == nil then
      timeout = cfg.timeout[vim.log.levels.INFO]
    end
  end
  if timeout and timeout > 0 then
    local timer = uv.new_timer()
    a.timer = timer
    timer:start(
      timeout,
      0,
      vim.schedule_wrap(function()
        close_entry(a)
      end)
    )
  end

  reflow()
  return win
end

--- How many toasts are currently visible.
function M.count()
  return #active
end

--- Close every currently-visible toast immediately — leaves the
--- history untouched, this only affects the popups.
function M.dismiss_all()
  for i = #active, 1, -1 do
    close_entry(active[i])
  end
end

--- Test/dev-only: same as `M.dismiss_all` — a named alias so callers
--- resetting several `mep.notify.*` modules at once don't need to know
--- this one's reset happens to just be "close everything".
function M._reset()
  M.dismiss_all()
end

return M

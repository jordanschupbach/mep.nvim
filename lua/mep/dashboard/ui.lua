--- Rendering for mep.dashboard: centers content in the target window and
--- writes it into the target buffer (which, for the startup use case, is
--- Neovim's own initial empty buffer — the dashboard takes it over rather
--- than opening a new window, same as replacing the built-in intro).
local M = {}

local ns = vim.api.nvim_create_namespace('mep_dashboard')

--- Configure `buf` as a non-editable dashboard scratch buffer.
function M.prepare_buffer(buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = 'mep-dashboard'
end

-- The window-local options M.prepare_window overrides, so
-- M.restore_window knows what to put back.
local WINDOW_OPTS = { 'number', 'relativenumber', 'signcolumn', 'fillchars' }

--- Strip `win`'s gutter for the dashboard: no number/relative-number
--- column, no sign column (there's nothing meaningful to show there —
--- the content is just centered static text), and no `~` end-of-buffer
--- filler past it (`content.lua`'s intro recreation is deliberately
--- shorter than the window, and real `~`s would otherwise crowd the
--- centered block). Window-local only — `vim.wo[win]`, not `vim.o` —
--- and returns the previous values so `M.restore_window` can put them
--- back once this window stops showing the dashboard (it's a real,
--- reused window, not a throwaway one — see `mep.dashboard.dashboard`'s
--- own `open()`).
function M.prepare_window(win)
  local saved = {}
  for _, opt in ipairs(WINDOW_OPTS) do
    saved[opt] = vim.wo[win][opt]
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].fillchars = 'eob: '
  return saved
end

--- Undo `prepare_window`: put `win`'s saved option values back. A no-op
--- if `win` has since closed.
function M.restore_window(win, saved)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  for _, opt in ipairs(WINDOW_OPTS) do
    vim.wo[win][opt] = saved[opt]
  end
end

--- Horizontally center each line individually (by its own display width)
--- and vertically center the whole block, within `width` x `height`.
function M.center(lines, width, height)
  local centered = {}
  for _, line in ipairs(lines) do
    local pad = math.floor((width - vim.fn.strdisplaywidth(line)) / 2)
    centered[#centered + 1] = pad > 0 and (string.rep(' ', pad) .. line) or line
  end

  local top_pad = math.max(0, math.floor((height - #centered) / 2))
  local out = {}
  for _ = 1, top_pad do
    out[#out + 1] = ''
  end
  for _, line in ipairs(centered) do
    out[#out + 1] = line
  end
  return out
end

-- A line made up of nothing but the "█" block character and whitespace
-- (i.e. content.lua's logo, or any custom-content lookalike). Checked
-- with gsub rather than a Lua character class: "█" is 3 UTF-8 bytes, and
-- Lua patterns match by byte, so a class like [█ ] wouldn't do what it
-- looks like it does.
local function is_logo_line(line)
  if not line:find('█', 1, true) then
    return false
  end
  return line:gsub('█', ''):gsub('%s', '') == ''
end

-- Neovim's own intro screen is drawn straight to the screen grid (see
-- content.lua), so there's no highlight scheme to introspect or copy —
-- this is a hand-designed one, using simple pattern matching so it also
-- picks up naturally on custom `content` that happens to look similar
-- (e.g. a URL in a user-supplied line still gets linked).
local function highlight_ranges(line)
  if is_logo_line(line) then
    return { { 0, #line, 'MepDashboardLogo' } }
  end

  -- A whole "NVIM v1.2.3" / "MEP v1.2.3" style version line (padding from
  -- centering included).
  if line:match('^%s*%u+%s+v%d+%.%d+%.%d+%s*$') then
    return { { 0, #line, 'MepDashboardVersion' } }
  end

  local ranges = {}
  local url_s, url_e = line:find('https?://%S+')
  if url_s then
    ranges[#ranges + 1] = { url_s - 1, url_e, 'MepDashboardLink' }
  end
  -- "type  :help nvim<Enter>  if you are new!" style command hints.
  local cmd_s, cmd_e = line:find(':.-<Enter>')
  if cmd_s then
    ranges[#ranges + 1] = { cmd_s - 1, cmd_e, 'MepDashboardCommand' }
  end
  return ranges
end

--- Write `lines` into `buf` (already-centered or not, caller's choice),
--- applying highlight_ranges()'s scheme, and leave the buffer
--- unmodifiable.
function M.render(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(lines) do
    for _, r in ipairs(highlight_ranges(line)) do
      pcall(vim.api.nvim_buf_add_highlight, buf, ns, r[3], i - 1, r[1], r[2])
    end
  end
  vim.bo[buf].modifiable = false
end

return M

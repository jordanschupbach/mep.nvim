--- Dashboard content generation. The default recreates Neovim's own
--- startup message (`:h :intro`) — but that message is drawn directly
--- onto the screen grid by Neovim itself, bypassing the message/echo
--- history entirely, so it cannot actually be captured through any Lua
--- API (`vim.fn.execute('intro')` reliably returns an empty string).
--- This is a hand-built reproduction of its stable wording instead, with
--- the version number (and the "news" help tag) always computed from the
--- Neovim that's actually running, so it never goes stale. The mep.nvim
--- version line below it is likewise read live from mep.version, the
--- plugin's own single source of truth for its version number.
local M = {}

-- A block-character "N", checked (by inspecting the actual compiled
-- Neovim 0.12 binary's embedded strings, not just the docs) not to be
-- part of Neovim's own :intro screen — there's no ASCII art there to
-- recreate. This is a from-scratch addition. All rows are the same
-- display width (10), so mep.dashboard.ui.center() keeps it a clean
-- block; ui.lua's highlight_ranges() recognizes it by being made
-- entirely of "█" and spaces.
M.LOGO = {
  '██      ██',
  '████    ██',
  '██  ██  ██',
  '██    ████',
  '██      ██',
}

function M.default()
  local v = vim.version()
  local nvim_version = string.format('NVIM v%d.%d.%d', v.major, v.minor, v.patch)
  local news_tag = string.format('v%d.%d', v.major, v.minor)

  local mv = require('mep.version')
  local mep_version = string.format('MEP v%d.%d.%d', mv.major, mv.minor, mv.patch)

  local lines = {}
  for _, l in ipairs(M.LOGO) do
    lines[#lines + 1] = l
  end

  vim.list_extend(lines, {
    '',
    nvim_version,
    mep_version,
    '',
    'Nvim is open source and freely distributable',
    'https://neovim.io/#chat',
    '',
    'type  :help nvim<Enter>       if you are new!',
    'type  :checkhealth<Enter>     to optimize Nvim',
    'type  :q<Enter>                to exit',
    'type  :help<Enter>             for help',
    '',
    'type  :help news<Enter> to see changes in ' .. news_tag,
    '',
    'Help poor children in Uganda!',
    'type  :help iccf<Enter>       for information',
  })

  return lines
end

--- Resolve `content` (as in mep.dashboard.config.options.content) into a
--- concrete list of lines: 'intro' or nil -> `M.default()`, a function is
--- called for its return value, a plain list is used as-is.
function M.resolve(content)
  if content == nil or content == 'intro' then
    return M.default()
  elseif type(content) == 'function' then
    return content()
  elseif type(content) == 'table' then
    return content
  end
  return M.default()
end

return M

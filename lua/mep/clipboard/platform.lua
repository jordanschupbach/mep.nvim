--- Session/tool detection for `mep.clipboard`'s own OSC 52 decision —
--- deliberately NOT a full reimplementation of Neovim's own native
--- clipboard provider (`runtime/autoload/provider/clipboard.vim`),
--- which already auto-detects pbcopy (macOS) / wl-copy+wl-paste
--- (Wayland) / xsel then xclip (X11) / win32yank.exe (WSL) with zero
--- configuration the moment any code touches the `+`/`*` registers —
--- reimplementing that here would just duplicate (and risk drifting
--- from) logic Neovim itself already maintains. This module only
--- answers the two questions `mep.clipboard.clipboard.setup` actually
--- needs: are we over SSH, and is there a local tool Neovim's own
--- provider could use anyway (in which case OSC 52 isn't needed).
local M = {}

--- Whether this Neovim is running inside an SSH session
--- (`$SSH_TTY`/`$SSH_CONNECTION` — the same two env vars OpenSSH itself
--- sets on the remote side for any session, interactive or not).
function M.is_ssh()
  return (vim.env.SSH_TTY ~= nil and vim.env.SSH_TTY ~= '')
    or (vim.env.SSH_CONNECTION ~= nil and vim.env.SSH_CONNECTION ~= '')
end

--- Whether a local clipboard tool Neovim's own native provider would
--- use is reachable on `PATH`, checked in the same order/gating that
--- provider does: `pbcopy` on macOS; `wl-copy`+`wl-paste` when
--- `$WAYLAND_DISPLAY` is set; `xsel` or `xclip` when `$DISPLAY` is set;
--- `win32yank.exe` otherwise (its own WSL/Windows-interop case).
function M.has_local_tool()
  if vim.fn.has('mac') == 1 then
    return vim.fn.executable('pbcopy') == 1
  end
  if vim.env.WAYLAND_DISPLAY and vim.env.WAYLAND_DISPLAY ~= '' then
    if vim.fn.executable('wl-copy') == 1 and vim.fn.executable('wl-paste') == 1 then
      return true
    end
  end
  if vim.env.DISPLAY and vim.env.DISPLAY ~= '' then
    if vim.fn.executable('xsel') == 1 or vim.fn.executable('xclip') == 1 then
      return true
    end
  end
  return vim.fn.executable('win32yank.exe') == 1
end

return M

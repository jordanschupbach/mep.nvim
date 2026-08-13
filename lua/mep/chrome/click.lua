--- Click dispatch for mep.chrome widgets. Statusline/winbar/tabline
--- click regions (`%N@FuncName@...%X`) only carry a numeric `minwid`
--- back to Neovim's click handler — the widget itself has to be
--- recovered from that number. `M.register(widget)` hands out a
--- stable id per widget *table identity* (stamped onto the widget the
--- first time it's seen, so re-rendering the same widget list — which
--- happens on every redraw — doesn't grow the registry), and `M.
--- dispatch` is the actual `_G.MepChromeClickDispatch` global function
--- referenced from `v:lua.MepChromeClickDispatch` in rendered format
--- strings (`v:lua` funcref is the same bridge `'foldexpr'`/
--- `'operatorfunc'`/`'tagfunc'` use — see `:help 'statusline'`'s
--- `%@` item).
local M = {}

local registry = {}
local next_id = 1

function M.register(widget)
  if widget._chrome_click_id then
    return widget._chrome_click_id
  end
  local id = next_id
  next_id = next_id + 1
  registry[id] = widget
  widget._chrome_click_id = id
  return id
end

--- The `%@` click-execute callback. `minwid`/`clicks`/`button`/`mods`
--- are exactly Neovim's own click-function arguments (`:help
--- 'statusline'`); the clicked window/buffer aren't among them, so
--- they're resolved via `getmousepos()` at click time instead.
function M.dispatch(minwid, clicks, button, mods)
  local widget = registry[tonumber(minwid)]
  if not widget or not widget.on_click then
    return
  end
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
  local ctx = {
    win = win,
    bufnr = ok and bufnr or vim.api.nvim_get_current_buf(),
    active = win == vim.api.nvim_get_current_win(),
  }
  widget.on_click(ctx, clicks, button, mods)
end

function M.enable()
  _G.MepChromeClickDispatch = M.dispatch
end

function M.disable()
  _G.MepChromeClickDispatch = nil
end

function M._reset()
  registry = {}
  next_id = 1
  M.disable()
end

return M

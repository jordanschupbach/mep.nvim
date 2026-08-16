--- A minimal single-line floating-window prompt, used by mep.ai's own
--- `gk` (send-selection-with-instructions) keymap to ask for extra
--- instructions without leaving the buffer or blocking on the
--- command-line's own `vim.fn.input()` — a real small popup was
--- specifically wanted over that. Neovim built-ins only (a scratch
--- buffer in a floating window), matching this project's zero-runtime-
--- dependency convention.
local M = {}

--- Open a small floating window with a one-line scratch buffer for
--- typing free text, starting in insert mode. `<CR>` (insert or normal
--- mode) confirms and calls `on_confirm(text)`; `<Esc>`, or leaving the
--- window any other way (`:q`, switching away, ...), cancels —
--- `on_confirm` is never called for an empty confirmed line either,
--- since there's no meaningful "empty instructions" case distinct from
--- "no popup at all". `title` (e.g. `"mep.ai: instructions"`), if
--- given, labels the window's border.
function M.prompt(title, on_confirm)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'

  local width = math.max(20, math.min(60, vim.o.columns - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - 3) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
    title = title and (' ' .. title .. ' ') or nil,
    title_pos = title and 'center' or nil,
  })

  -- Both the confirm/cancel keymaps below and the BufLeave autocmd can
  -- end up calling this — idempotent so whichever fires first wins and
  -- the rest are no-ops, instead of double-closing the window or
  -- double-firing on_confirm.
  local closed = false
  local function close(confirmed)
    if closed then
      return
    end
    closed = true
    local text = vim.api.nvim_buf_is_valid(buf) and (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '') or ''
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if confirmed and text ~= '' then
      on_confirm(text)
    end
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    close(true)
  end, { buffer = buf, desc = 'mep.ai: confirm popup input' })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    close(false)
  end, { buffer = buf, desc = 'mep.ai: cancel popup input' })
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      close(false)
    end,
  })

  vim.cmd.startinsert()
end

return M

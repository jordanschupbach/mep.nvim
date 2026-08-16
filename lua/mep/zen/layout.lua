--- Horizontal centering for zen mode: two blank, fixed-width side-
--- padding splits (`winfixwidth`, so later layout changes elsewhere
--- don't resize them away) squeeze `win` down toward `width` columns
--- rather than reflowing/resizing its own buffer — a real window, not a
--- virtual margin, the same "actual splits, not a trick" posture this
--- project's own float-based libraries take toward *their* own
--- isolation (`mep.sidebar`'s own `float = true`).
local M = {}

local function padding_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  return buf
end

--- Add a blank padding split of `width` columns on one side of the
--- *current* window (`'leftabove'`/`'rightbelow'`), leaving focus back
--- on `win` afterward. Returns the new window's id.
local function add_padding(win, direction, width)
  vim.api.nvim_set_current_win(win)
  vim.cmd(direction .. ' vsplit')
  local pad_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(pad_win, padding_buf())
  vim.wo[pad_win].winfixwidth = true
  vim.wo[pad_win].number = false
  vim.wo[pad_win].relativenumber = false
  vim.wo[pad_win].signcolumn = 'no'
  pcall(vim.api.nvim_win_set_width, pad_win, width)
  vim.api.nvim_set_current_win(win)
  return pad_win
end

--- Center `win` toward `width` columns by adding a blank padding split
--- on each side, sized to split the remainder evenly. Returns `{
--- left_win, right_win }`, or `nil` if `win` is already `width` columns
--- or narrower (nothing to pad).
function M.center(win, width)
  local total = vim.api.nvim_win_get_width(win)
  local pad = math.floor((total - width) / 2)
  if pad < 1 then
    return nil
  end
  local left_win = add_padding(win, 'leftabove', pad)
  local right_win = add_padding(win, 'rightbelow', pad)
  return { left_win = left_win, right_win = right_win }
end

--- Undo `M.center`: close both padding windows (a no-op for either that
--- has since closed on its own).
function M.uncenter(padding)
  if not padding then
    return
  end
  for _, w in ipairs({ padding.left_win, padding.right_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

return M

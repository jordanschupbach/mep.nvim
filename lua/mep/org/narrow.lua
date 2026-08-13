--- A practical, fold-based approximation of Emacs org-mode's buffer
--- narrowing: fold away everything before and after the target subtree
--- as two manual folds, so scrolling only shows it. Not true narrowing —
--- editing outside the folded regions is still technically possible —
--- but it gives the same "focused view" in the one way Neovim actually
--- supports (folds), without needing a second buffer/window.
local outline = require('mep.org.outline')

local M = {}

-- winid -> { foldmethod, foldenable, start, stop } for windows currently
-- narrowed, so widen() can restore exactly what narrow() overrode.
local narrowed = {}

--- Narrow `win` (showing `bufnr`) to the subtree at `lnum`. Returns true
--- on success, or nil if `lnum` isn't inside a headline or `win` is
--- already narrowed.
function M.narrow(bufnr, win, lnum)
  if narrowed[win] then
    return nil
  end
  local at = outline.current_headline(bufnr, lnum)
  if not at then
    return nil
  end

  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local stop = outline.subtree_end(bufnr, at)
  local saved = {
    foldmethod = vim.wo[win].foldmethod,
    foldenable = vim.wo[win].foldenable,
  }

  vim.api.nvim_win_call(win, function()
    vim.wo[win].foldmethod = 'manual'
    vim.cmd('normal! zE') -- clear any pre-existing manual folds first
    if at > 1 then
      vim.cmd(string.format('1,%dfold', at - 1))
    end
    if stop < last_line then
      vim.cmd(string.format('%d,%dfold', stop + 1, last_line))
    end
    pcall(vim.api.nvim_win_set_cursor, win, { at, 0 })
    vim.cmd('normal! zt')
  end)

  narrowed[win] = vim.tbl_extend('force', saved, { start = at, stop = stop })
  return true
end

--- Undo `narrow`, restoring `win`'s previous fold configuration
--- (re-triggering `foldexpr` recomputation if that's what it was).
--- Returns true, or nil if `win` wasn't narrowed.
function M.widen(win)
  local saved = narrowed[win]
  if not saved then
    return nil
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zE')
    vim.wo[win].foldmethod = saved.foldmethod
    vim.wo[win].foldenable = saved.foldenable
  end)
  narrowed[win] = nil
  return true
end

--- Whether `win` is currently narrowed.
function M.is_narrowed(win)
  return narrowed[win] ~= nil
end

return M

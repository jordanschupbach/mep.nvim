--- Extmark rendering for mep.hints: highlights each target's matched
--- span (`MepHintMatch`) and overlays its assigned label on top of the
--- span's own first columns (`MepHintLabel`), high priority so the
--- label wins over any existing syntax/treesitter highlight there.
local M = {}

local ns = vim.api.nvim_create_namespace('mep_hints')

--- Give MepHintMatch/MepHintLabel a visible default if nothing else
--- already has — `default = true` means a user's own
--- `:highlight MepHint... ...` (or a colorscheme that defines them)
--- wins over this.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, 'MepHintMatch', { link = 'Search', default = true })
  vim.api.nvim_set_hl(0, 'MepHintLabel', { link = 'ErrorMsg', default = true })
end

--- Clear every extmark this module has set in `bufnr`.
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

--- Render `targets` (mep.hints.targets' own `{lnum, col, len}` shape,
--- each additionally carrying its assigned `.label` string) into
--- `bufnr`, replacing whatever this module had rendered there before.
function M.show(bufnr, targets)
  M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, t in ipairs(targets) do
    if t.lnum >= 1 and t.lnum <= line_count then
      if t.len > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, t.lnum - 1, t.col, {
          end_col = t.col + t.len,
          hl_group = 'MepHintMatch',
          priority = 200,
        })
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, t.lnum - 1, t.col, {
        virt_text = { { t.label, 'MepHintLabel' } },
        virt_text_pos = 'overlay',
        priority = 201,
      })
    end
  end
end

return M

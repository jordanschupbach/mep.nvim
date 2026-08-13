--- Visually conceals the raw `[[...]]` syntax of org links, showing
--- only the description (or the bare target, when there's no
--- description) — real org-mode's link display. A separate module from
--- mep.org.link since this is pure extmark bookkeeping with no
--- link-semantics of its own; the real grammar has no dedicated link
--- node to hang a tree-sitter `@conceal` capture off of (confirmed
--- while building Phase 0's highlight query), so this manages its own
--- extmarks directly instead, using mep.org.link.find to locate spans.
--- Needs 'conceallevel' >= 2 on the window to actually take visual
--- effect; mep.org.org sets that (plus 'concealcursor') per-window when
--- `conceal_links` is enabled.
local link_mod = require('mep.org.link')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_org_link_conceal')

--- Clear every concealment extmark this module has set in `bufnr`.
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Recompute concealment extmarks for every link in `bufnr`, replacing
--- whatever was there before. For `[[target][description]]`, conceals
--- `[[target][` and the trailing `]]`, leaving just `description`
--- visible. For a bare `[[target]]`, conceals just the two bracket
--- pairs, leaving `target` visible.
function M.apply(bufnr)
  M.clear(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local init = 1
    while true do
      local s, e, target, description = link_mod.find(line, init)
      if not s then
        break
      end
      if description then
        local desc_start = s + 4 + #target -- 1-based position of description's first char
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, s - 1, { end_col = desc_start - 1, conceal = '' })
      else
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, s - 1, { end_col = s + 1, conceal = '' })
      end
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, e - 2, { end_col = e, conceal = '' })
      init = e + 1
    end
  end
end

return M

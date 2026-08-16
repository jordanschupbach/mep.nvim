--- Extmark rendering for mep.colorizer: a `MepColorizerBg_<hex>`/
--- `MepColorizerFg_<hex>` highlight group per distinct color actually
--- seen (cached, defined once), applied either as a background over the
--- matched text (`mode = 'background'`) or as an inline swatch
--- character placed just before it, leaving the match's own text
--- untouched (`mode = 'swatch'`).
local patterns = require('mep.colorizer.patterns')

local M = {}

local ns = vim.api.nvim_create_namespace('mep_colorizer')
local defined = {} -- group name -> true, so nvim_set_hl only runs once per color

--- Perceived-brightness (ITU-R BT.601 luma — the same simple heuristic
--- real colorizers, e.g. norcalli/nvim-colorizer.lua, use for this)
--- black/white text color that stays readable over `hex`'s background.
local function contrast_fg(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  local luma = 0.299 * r + 0.587 * g + 0.114 * b
  return luma > 140 and '#000000' or '#ffffff'
end

local function bg_group(hex)
  local name = 'MepColorizerBg_' .. hex:sub(2)
  if not defined[name] then
    vim.api.nvim_set_hl(0, name, { bg = hex, fg = contrast_fg(hex) })
    defined[name] = true
  end
  return name
end

local function fg_group(hex)
  local name = 'MepColorizerFg_' .. hex:sub(2)
  if not defined[name] then
    vim.api.nvim_set_hl(0, name, { fg = hex })
    defined[name] = true
  end
  return name
end
M.bg_group = bg_group
M.fg_group = fg_group

--- Clear every extmark this module has set in `bufnr`.
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

--- Rescan every line of `bufnr` and re-render its color matches,
--- replacing whatever this module had rendered there before. `mode`/
--- `swatch_char` are `mep.colorizer.config.defaults`'s own fields.
function M.render(bufnr, mode, swatch_char)
  M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    for _, m in ipairs(patterns.find_all(line)) do
      if mode == 'swatch' then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, m.start_col - 1, {
          virt_text = { { swatch_char, fg_group(m.hex) } },
          -- 'inline' (Neovim >= 0.10) shifts the following text right
          -- rather than overlaying it, so the swatch sits *before* the
          -- match without hiding any of it — an older Neovim just
          -- silently skips the swatch (pcall) rather than erroring.
          virt_text_pos = 'inline',
        })
      else
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, m.start_col - 1, {
          end_col = m.end_col,
          hl_group = bg_group(m.hex),
        })
      end
    end
  end
end

return M

--- Renders a palette as a color swatch — one line per field, a solid
--- block of that field's own color plus its name and hex value — into
--- the picker's preview sidebar (`mep.theme.theme.picker`'s own
--- `preview` callback). A picker `preview` callback always gets
--- `(item, preview_buf, preview_win)` (`mep.picker.engine`'s own
--- `Picker:update_preview`); this is the `preview_buf` renderer,
--- alongside `mep.theme.M.apply` recoloring the whole editor live —
--- together you get both "here's exactly what red/green/... look like
--- side by side" and "here's what your own buffers will actually look
--- like", at the same time, on every selection move.
local M = {}

local ns = vim.api.nvim_create_namespace('mep_theme_swatch')

-- bg/bg_alt/fg/fg_alt first (the base the rest sits on), then the
-- seven accent hues, then border — mirrors mep.theme.palettes' own
-- header-comment field order.
local FIELDS = { 'bg', 'bg_alt', 'fg', 'fg_alt', 'red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'border' }

local SWATCH_WIDTH = 8

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Render `name`'s `palette` (already normalized — see `mep.theme.
--- engine.normalize` — so `bg_alt`/`fg_alt` are always present even for
--- a palette that never set them) into `buf` as one swatch line per
--- field in `FIELDS`. A no-op for an invalid/already-closed buffer
--- (e.g. a test that calls a captured `preview(item)` with no
--- buf/win at all) or a palette missing a field entirely.
function M.render(buf, name, palette)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local lines = { name or '', '' }
  local swatch_rows = {} -- 1-based line index (into `lines`) -> field name
  for _, field in ipairs(FIELDS) do
    local hex = palette[field]
    if hex then
      local label = string.format('  %-8s', field)
      local swatch = string.rep(' ', SWATCH_WIDTH)
      lines[#lines + 1] = label .. ' ' .. swatch .. '  ' .. hex
      swatch_rows[#lines] = field
    end
  end
  set_lines(buf, lines)

  for lnum, field in pairs(swatch_rows) do
    local hex = palette[field]
    local group = 'MepThemeSwatch_' .. field
    vim.api.nvim_set_hl(0, group, { bg = hex })
    local label_width = #(string.format('  %-8s', field)) + 1 -- + the space before the swatch
    pcall(
      vim.api.nvim_buf_add_highlight,
      buf,
      ns,
      group,
      lnum - 1,
      label_width,
      label_width + SWATCH_WIDTH
    )
  end
end

return M

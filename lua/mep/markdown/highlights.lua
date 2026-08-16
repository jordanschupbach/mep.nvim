--- Distinct highlight groups for markdown structure — headers (H1-H6,
--- `@markup.heading.1`..`.6`) and bold/emphasis (`@markup.strong`/
--- `@markup.italic`).
---
--- Neovim's own bundled markdown `highlights.scm` already emits
--- `@markup.heading.1`..`.6` per level (`atx_heading`/`setext_heading`
--- nodes, matched against which marker they contain) — `mep.theme.
--- engine`'s own SPECS table only has the generic `@markup.heading`
--- fallback every level currently resolves through, so `.1`-`.6` are
--- free for `M.define_headers` to claim outright with a plain `link` +
--- `default = true`, same as every other `MepXxx` group in this
--- codebase.
---
--- `@markup.strong`/`@markup.italic` are different: `mep.theme.engine`
--- *does* already explicitly set those two (`bold = true`/`italic =
--- true`, no color), so `default = true` would be a no-op there — `M.
--- define_emphasis` instead copies whatever `Constant`/`String`
--- currently resolves to and layers the weight back on top, forcing
--- the merged result in (no `default`) rather than linking outright
--- (a plain `link` would replace the whole definition, losing the
--- bold/italic weight rather than adding color to it).
local M = {}

local HEADING_LINKS = { 'Title', 'Function', 'Keyword', 'Identifier', 'Type', 'Comment' }

local function link_with(name, target, extra)
  local ok, resolved = pcall(vim.api.nvim_get_hl, 0, { name = target, link = false })
  if not ok then
    resolved = {}
  end
  resolved = vim.tbl_extend('force', resolved, extra or {})
  vim.api.nvim_set_hl(0, name, resolved)
end

--- (Re)define `@markup.heading.1`..`.6`. Safe to call repeatedly (e.g.
--- on every real `:colorscheme`/`mep.theme.apply` change) — `default =
--- true` only takes effect the first time any given group is unset.
function M.define_headers()
  for level, target in ipairs(HEADING_LINKS) do
    vim.api.nvim_set_hl(0, '@markup.heading.' .. level, { link = target, default = true })
  end
end

--- (Re)define `@markup.strong`/`@markup.italic` with color layered
--- onto their existing weight. Unlike `define_headers`, this always
--- overwrites (no `default`) — call it again after any real
--- colorscheme change to pick up that theme's own `Constant`/`String`.
function M.define_emphasis()
  link_with('@markup.strong', 'Constant', { bold = true })
  link_with('@markup.italic', 'String', { italic = true })
end

--- (Re)define the three groups `mep.markdown.tables` paints its
--- overlay extmarks with: muted borders, bold header cells (reusing
--- `@markup.strong` above rather than picking a color of its own), and
--- plain-`Normal`-look body cells. `default = true`, same reasoning as
--- `define_headers`.
function M.define_tables()
  vim.api.nvim_set_hl(0, 'MepMarkdownTableBorder', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'MepMarkdownTableHeader', { link = '@markup.strong', default = true })
  vim.api.nvim_set_hl(0, 'MepMarkdownTableCell', { link = 'Normal', default = true })
end

--- (Re)define `MepMarkdownCodeBlock`, the background band `mep.
--- markdown.codeblocks` paints behind fenced code — linked to
--- `CursorLine` (a "just a bit different from Normal" bg every theme
--- already defines) rather than a hardcoded color. `default = true`,
--- same reasoning as `define_headers`.
function M.define_code_blocks()
  vim.api.nvim_set_hl(0, 'MepMarkdownCodeBlock', { link = 'CursorLine', default = true })
end

--- (Re)define `MepMarkdownFrontmatter`, the background band `mep.
--- markdown.frontmatter` paints behind a YAML/TOML front-matter block —
--- linked to `ColorColumn` (a real, standard "subtle marker background"
--- group every theme already defines, distinct from `CursorLine` above
--- so a front-matter block and a code block don't read identically).
--- `default = true`, same reasoning as `define_headers`.
function M.define_frontmatter()
  vim.api.nvim_set_hl(0, 'MepMarkdownFrontmatter', { link = 'ColorColumn', default = true })
end

return M

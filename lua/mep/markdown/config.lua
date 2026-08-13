local M = {}

M.defaults = {
  -- Installs the markdown/markdown_inline tree-sitter parsers (if
  -- missing) and activates treesitter highlighting for markdown
  -- buffers — without this, headers/bold/emphasis have nothing to
  -- render distinctly at all, regardless of headers/emphasis below.
  highlight = true,
  -- Distinct per-level (H1-H6) heading colors — mep.markdown.
  -- highlights' own `@markup.heading.1`..`.6` groups, linked to
  -- Title/Function/Keyword/Identifier/Type/Comment respectively.
  headers = true,
  -- Distinct bold/emphasis colors, on top of the bold/italic weight
  -- mep.theme.engine's own `@markup.strong`/`@markup.italic` already
  -- apply — mep.markdown.highlights' own overrides, colored like
  -- Constant/String respectively.
  emphasis = true,
  -- One sign-column marker per heading line, showing its level
  -- (`gutter_symbols`, one entry per level 1-6) in that level's own
  -- heading color. Circled digits by default (①-⑥) so it reads as an
  -- icon at a glance rather than a plain gutter number.
  gutter = true,
  gutter_symbols = { '①', '②', '③', '④', '⑤', '⑥' },
  -- Re-renders GFM pipe tables as real box-drawn tables (aligned
  -- columns, ┌─┬─┐/├─┼─┤/└─┴─┘ borders) via overlay extmarks — the
  -- buffer's actual text stays plain markdown underneath, so editing
  -- still works normally; the raw line under the cursor is left
  -- unrendered so you can see/edit what you're actually typing.
  tables = true,
  -- Shades the background of fenced (``` / ~~~) code blocks so they
  -- read as a distinct block instead of blending into surrounding
  -- prose.
  code_blocks = true,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M

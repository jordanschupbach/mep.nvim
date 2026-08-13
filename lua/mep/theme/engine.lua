--- Turns any `mep.theme.palettes`-shaped palette into a full Neovim
--- highlight set. One shared, data-driven renderer for every theme —
--- `SPECS` below maps each highlight group to *palette field names*
--- (resolved against whichever palette is passed in), not literal
--- colors, so adding a theme is just adding a palette, never touching
--- this file. `M.build` (pure — never touches a real highlight group)
--- is what `spec/mep/theme/engine_spec.lua` exercises directly;
--- `M.apply` is the thin impure wrapper that actually calls
--- `nvim_set_hl`.
---
--- mep's own custom highlight groups (`MepGitAdd`, `MepSidebarTitle`,
--- `MepWindowTab`, ...) all `link` to standard groups defined here
--- (`plugin/mep.lua`'s own `set_highlights()`, `default = true`) — so
--- getting groups like `DiffAdd`/`Title`/`TabLine` right here is
--- already enough for every mep library's own chrome to look right
--- under any of these themes, with no extra work needed per-library.
local M = {}

--- Fields a palette can define — the required ones this module will
--- error without, and the optional ones `M.normalize` fills in from a
--- sensible fallback field when a palette omits them (a minimal
--- ~11-field palette is enough for a coherent result; see `mep.theme.
--- palettes`'s own header comment for the full field list).
local REQUIRED_FIELDS = { 'bg', 'fg', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'orange', 'border' }
local FALLBACKS = {
  bg_alt = 'bg',
  bg_float = 'bg_alt',
  fg_alt = 'fg',
  selection = 'border',
  accent = 'blue',
}

--- `palette` with every optional field present, falling back per
--- `FALLBACKS` (applied in dependency order — `bg_float` can fall back
--- to a `bg_alt` that was itself just filled in from `bg`) — never
--- mutates `palette` itself.
function M.normalize(palette)
  local p = vim.tbl_extend('force', {}, palette)
  for field, fallback in pairs(FALLBACKS) do
    if p[field] == nil then
      p[field] = p[fallback]
    end
  end
  return p
end

--- `palette` defines every field `M.normalize` can't fill in on its
--- own — a list of missing field names, empty if it's valid.
function M.missing_fields(palette)
  local missing = {}
  for _, field in ipairs(REQUIRED_FIELDS) do
    if palette[field] == nil then
      missing[#missing + 1] = field
    end
  end
  if palette.dark == nil then
    missing[#missing + 1] = 'dark'
  end
  return missing
end

-- Each entry is either `{ link = 'OtherGroup' }` or a table of
-- highlight attributes where `fg`/`bg`/`sp` are *palette field names*
-- (resolved in `M.build`), and `bold`/`italic`/`underline`/`reverse`/
-- `nocombine` are literal booleans passed straight through.
local SPECS = {
  -- Core UI
  Normal = { fg = 'fg', bg = 'bg' },
  NormalNC = { fg = 'fg', bg = 'bg' },
  NormalFloat = { fg = 'fg', bg = 'bg_float' },
  FloatBorder = { fg = 'border', bg = 'bg_float' },
  FloatTitle = { fg = 'accent', bg = 'bg_float', bold = true },
  ColorColumn = { bg = 'bg_alt' },
  Conceal = { fg = 'fg_alt' },
  Cursor = { fg = 'bg', bg = 'fg' },
  CursorColumn = { bg = 'bg_alt' },
  CursorLine = { bg = 'bg_alt' },
  CursorLineNr = { fg = 'accent', bold = true },
  LineNr = { fg = 'fg_alt' },
  Directory = { fg = 'blue' },
  EndOfBuffer = { fg = 'bg_alt' },
  FoldColumn = { fg = 'fg_alt', bg = 'bg' },
  Folded = { fg = 'fg_alt', bg = 'bg_alt' },
  SignColumn = { fg = 'fg', bg = 'bg' },
  MatchParen = { bg = 'border', bold = true },
  ModeMsg = { fg = 'fg', bold = true },
  MoreMsg = { fg = 'green' },
  MsgArea = { fg = 'fg' },
  ErrorMsg = { fg = 'red', bold = true },
  WarningMsg = { fg = 'yellow' },
  Question = { fg = 'green' },
  NonText = { fg = 'border' },
  Whitespace = { fg = 'border' },
  SpecialKey = { fg = 'border' },
  Pmenu = { fg = 'fg', bg = 'bg_alt' },
  PmenuSel = { fg = 'bg', bg = 'accent', bold = true },
  PmenuSbar = { bg = 'bg_alt' },
  PmenuThumb = { bg = 'border' },
  Search = { fg = 'bg', bg = 'yellow' },
  IncSearch = { fg = 'bg', bg = 'orange' },
  CurSearch = { fg = 'bg', bg = 'orange' },
  QuickFixLine = { bg = 'bg_alt', bold = true },
  SpellBad = { sp = 'red', underline = true },
  SpellCap = { sp = 'yellow', underline = true },
  SpellLocal = { sp = 'cyan', underline = true },
  SpellRare = { sp = 'purple', underline = true },
  StatusLine = { fg = 'fg', bg = 'bg_alt' },
  StatusLineNC = { fg = 'fg_alt', bg = 'bg_alt' },
  WinBar = { fg = 'fg', bg = 'bg' },
  WinBarNC = { fg = 'fg_alt', bg = 'bg' },
  TabLine = { fg = 'fg_alt', bg = 'bg_alt' },
  TabLineFill = { bg = 'bg_alt' },
  TabLineSel = { fg = 'bg', bg = 'accent', bold = true },
  Title = { fg = 'accent', bold = true },
  Visual = { bg = 'selection' },
  VisualNOS = { bg = 'selection' },
  WildMenu = { fg = 'bg', bg = 'accent' },
  WinSeparator = { fg = 'border' },
  VertSplit = { fg = 'border' },

  -- Classic syntax groups
  Comment = { fg = 'fg_alt', italic = true },
  Constant = { fg = 'orange' },
  String = { fg = 'green' },
  Character = { fg = 'green' },
  Number = { fg = 'orange' },
  Boolean = { fg = 'orange' },
  Float = { fg = 'orange' },
  Identifier = { fg = 'fg' },
  Function = { fg = 'blue', bold = true },
  Statement = { fg = 'red' },
  Conditional = { fg = 'red' },
  Repeat = { fg = 'red' },
  Label = { fg = 'red' },
  Operator = { fg = 'fg' },
  Keyword = { fg = 'red' },
  Exception = { fg = 'red' },
  PreProc = { fg = 'yellow' },
  Include = { fg = 'blue' },
  Define = { fg = 'purple' },
  Macro = { fg = 'purple' },
  PreCondit = { fg = 'yellow' },
  Type = { fg = 'yellow' },
  StorageClass = { fg = 'yellow' },
  Structure = { fg = 'yellow' },
  Typedef = { fg = 'yellow' },
  Special = { fg = 'orange' },
  SpecialChar = { fg = 'orange' },
  Tag = { fg = 'orange' },
  Delimiter = { fg = 'fg' },
  SpecialComment = { fg = 'fg_alt' },
  Debug = { fg = 'red' },
  Underlined = { underline = true },
  Ignore = { fg = 'fg_alt' },
  Error = { fg = 'red', bold = true },
  Todo = { fg = 'bg', bg = 'yellow', bold = true },

  -- Diff
  DiffAdd = { fg = 'green', bg = 'bg_alt' },
  DiffChange = { fg = 'yellow', bg = 'bg_alt' },
  DiffDelete = { fg = 'red', bg = 'bg_alt' },
  DiffText = { fg = 'blue', bg = 'bg_alt', bold = true },

  -- Diagnostics
  DiagnosticError = { fg = 'red' },
  DiagnosticWarn = { fg = 'yellow' },
  DiagnosticInfo = { fg = 'blue' },
  DiagnosticHint = { fg = 'cyan' },
  DiagnosticOk = { fg = 'green' },
  DiagnosticUnderlineError = { sp = 'red', underline = true },
  DiagnosticUnderlineWarn = { sp = 'yellow', underline = true },
  DiagnosticUnderlineInfo = { sp = 'blue', underline = true },
  DiagnosticUnderlineHint = { sp = 'cyan', underline = true },
  DiagnosticUnderlineOk = { sp = 'green', underline = true },

  -- Treesitter (modern @-captures) — mostly links onto the classic
  -- groups above (one place to tune either), a few given their own
  -- entry where linking would lose a distinction worth keeping.
  ['@variable'] = { fg = 'fg' },
  ['@variable.builtin'] = { fg = 'orange' },
  ['@variable.parameter'] = { fg = 'fg' },
  ['@variable.member'] = { fg = 'fg' },
  ['@constant'] = { link = 'Constant' },
  ['@constant.builtin'] = { fg = 'orange', bold = true },
  ['@module'] = { fg = 'yellow' },
  ['@namespace'] = { fg = 'yellow' },
  ['@string'] = { link = 'String' },
  ['@string.escape'] = { fg = 'orange' },
  ['@string.special'] = { fg = 'orange' },
  ['@character'] = { link = 'Character' },
  ['@number'] = { link = 'Number' },
  ['@boolean'] = { link = 'Boolean' },
  ['@float'] = { link = 'Float' },
  ['@function'] = { link = 'Function' },
  ['@function.builtin'] = { fg = 'blue', bold = true },
  ['@function.call'] = { link = 'Function' },
  ['@function.macro'] = { fg = 'purple' },
  ['@method'] = { link = 'Function' },
  ['@method.call'] = { link = 'Function' },
  ['@constructor'] = { fg = 'yellow' },
  ['@parameter'] = { fg = 'fg' },
  ['@keyword'] = { link = 'Keyword' },
  ['@keyword.function'] = { link = 'Keyword' },
  ['@keyword.operator'] = { fg = 'red' },
  ['@keyword.return'] = { link = 'Keyword' },
  ['@keyword.import'] = { link = 'Include' },
  ['@conditional'] = { link = 'Conditional' },
  ['@repeat'] = { link = 'Repeat' },
  ['@label'] = { link = 'Label' },
  ['@operator'] = { link = 'Operator' },
  ['@exception'] = { link = 'Exception' },
  ['@type'] = { link = 'Type' },
  ['@type.builtin'] = { fg = 'yellow', italic = true },
  ['@attribute'] = { fg = 'purple' },
  ['@property'] = { fg = 'fg' },
  ['@field'] = { fg = 'fg' },
  ['@punctuation.delimiter'] = { fg = 'fg_alt' },
  ['@punctuation.bracket'] = { fg = 'fg' },
  ['@punctuation.special'] = { fg = 'orange' },
  ['@comment'] = { link = 'Comment' },
  ['@tag'] = { link = 'Tag' },
  ['@tag.attribute'] = { fg = 'yellow' },
  ['@tag.delimiter'] = { fg = 'fg_alt' },
  ['@text.title'] = { link = 'Title' },
  ['@text.literal'] = { fg = 'green' },
  ['@text.uri'] = { fg = 'blue', underline = true },
  ['@markup.heading'] = { link = 'Title' },
  ['@markup.link'] = { fg = 'blue', underline = true },
  ['@markup.raw'] = { fg = 'green' },
  ['@markup.italic'] = { italic = true },
  ['@markup.strong'] = { bold = true },
}

--- `SPECS` resolved against `palette` (normalized via `M.normalize`
--- first) into `{ [group] = highlight_opts }`, ready for `nvim_set_hl`
--- — pure, never touches a real highlight group.
function M.build(palette)
  local p = M.normalize(palette)
  local groups = {}
  for group, spec in pairs(SPECS) do
    if spec.link then
      groups[group] = { link = spec.link }
    else
      local hl = {}
      if spec.fg then
        hl.fg = p[spec.fg]
      end
      if spec.bg then
        hl.bg = p[spec.bg]
      end
      if spec.sp then
        hl.sp = p[spec.sp]
      end
      if spec.bold then
        hl.bold = true
      end
      if spec.italic then
        hl.italic = true
      end
      if spec.underline then
        hl.underline = true
      end
      if spec.reverse then
        hl.reverse = true
      end
      groups[group] = hl
    end
  end
  return groups
end

--- Apply `palette` to the running editor: `hi clear` + `syntax reset`
--- (dropping whatever the previous colorscheme left behind), set
--- `'background'`/`vim.g.colors_name`, `nvim_set_hl` every group
--- `M.build` produces, then fire a real `ColorScheme` autocmd event —
--- `hi clear`/`nvim_set_hl` don't trigger one on their own (only the
--- `:colorscheme` command does), and mep's own custom highlight groups
--- (`MepGitAdd`, `MepSidebarTitle`, `MepWindowTab`, ...) all `link` to
--- standard groups `M.build` just redefined via `plugin/mep.lua`'s own
--- `ColorScheme`-triggered `set_highlights()` — without firing this
--- event ourselves, that link would go stale (still pointing at
--- whatever the *previous* theme's colors were) the moment `hi clear`
--- wiped it, since nothing else here would ever re-establish it.
function M.apply(palette)
  vim.cmd('highlight clear')
  if vim.fn.exists('syntax_on') == 1 then
    vim.cmd('syntax reset')
  end
  vim.o.background = palette.dark and 'dark' or 'light'
  vim.g.colors_name = palette.name

  for group, hl in pairs(M.build(palette)) do
    vim.api.nvim_set_hl(0, group, hl)
  end

  vim.api.nvim_exec_autocmds('ColorScheme', { modeline = false })
end

return M

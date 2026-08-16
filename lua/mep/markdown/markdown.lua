--- mep's markdown library: distinct per-level heading colors, distinct
--- bold/emphasis colors, a heading-level marker in the sign column,
--- box-drawn GFM tables, shaded fenced-code-block/front-matter
--- backgrounds, GFM task-list checkbox toggling, heading-depth folding,
--- and link/emphasis concealment — the last three mirroring `mep.org`'s
--- own checkbox/fold/linkconceal handling. Deliberately no outline/TODO/
--- agenda machinery comparable to `mep.org`'s (a much larger, structural
--- org-mode implementation) — just visual styling and the handful of
--- editing conveniences GFM markdown itself actually has an equivalent
--- for.
local config = require('mep.markdown.config')
local highlights = require('mep.markdown.highlights')
local gutter = require('mep.markdown.gutter')
local tables = require('mep.markdown.tables')
local codeblocks = require('mep.markdown.codeblocks')
local checkbox = require('mep.markdown.checkbox')
local fold = require('mep.markdown.fold')
local linkconceal = require('mep.markdown.linkconceal')
local frontmatter = require('mep.markdown.frontmatter')

local M = {}
M.highlights = highlights
M.gutter = gutter
M.tables = tables
M.codeblocks = codeblocks
M.checkbox = checkbox
M.fold = fold
M.linkconceal = linkconceal
M.frontmatter = frontmatter

local augroup = nil

--- Installs the markdown/markdown_inline tree-sitter parsers (if
--- missing) and starts treesitter highlighting for `bufnr` — the outer
--- 'markdown' grammar handles headings/lists/block quotes/etc
--- directly; 'markdown_inline' (bold/italic/links inside paragraph and
--- heading text) is only ever pulled in as an *injected* sub-parser
--- (`:help treesitter-injections`), so it's installed but never itself
--- passed to `enable_for_buffer`.
local function ensure_highlight(bufnr)
  local install = require('mep.treesitter.install')
  local activate = require('mep.treesitter.activate')
  local remaining = 2
  local all_ok = true
  local function maybe_activate(ok)
    remaining = remaining - 1
    all_ok = all_ok and ok ~= false
    if remaining == 0 and all_ok and vim.api.nvim_buf_is_valid(bufnr) then
      activate.enable_for_buffer(bufnr, { highlight = true })
    end
  end
  install.install('markdown', maybe_activate)
  install.install('markdown_inline', maybe_activate)
end

--- `mep.org.org`'s own `apply_fold`, mirrored: explicitly resets to
--- Vim's default ('manual') when disabled, rather than just skipping —
--- 'foldmethod' is window-local, so a window that previously showed a
--- fold=true buffer would otherwise keep stale 'expr' foldmethod/
--- foldexpr for a later buffer whose own config says fold=false.
local function apply_fold(bufnr, options)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if options.fold then
      vim.wo[win].foldmethod = 'expr'
      vim.wo[win].foldexpr = "v:lua.require'mep.markdown.fold'.foldexpr()"
    else
      vim.wo[win].foldmethod = 'manual'
    end
  end
end

--- `mep.org.org`'s own `apply_conceal`, mirrored: sets conceallevel/
--- concealcursor on every window already showing `bufnr`, renders once
--- immediately, and keeps it current on further edits.
local function apply_conceal(bufnr, options)
  if not options.conceal then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].conceallevel = 2
    vim.wo[win].concealcursor = 'nc'
  end
  linkconceal.apply(bufnr)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      linkconceal.apply(bufnr)
    end,
  })
end

local function bind_keymaps(bufnr, options)
  local km = options.keymaps
  local map_opts = { buffer = bufnr, nowait = true, silent = true }
  local function map_all(lhs_list, fn, desc)
    for _, lhs in ipairs(lhs_list or {}) do
      vim.keymap.set('n', lhs, fn, vim.tbl_extend('force', map_opts, { desc = desc }))
    end
  end

  if options.checkbox then
    map_all(km.toggle_checkbox, function()
      checkbox.toggle(bufnr, vim.api.nvim_win_get_cursor(0)[1])
    end, 'mep.markdown: toggle checkbox under cursor')
  end
  if options.fold then
    map_all(km.toggle_fold, function()
      vim.cmd('normal! za')
    end, 'mep.markdown: toggle fold under cursor')
  end
end

local function activate_markdown_buffer(bufnr, options)
  if options.highlight then
    ensure_highlight(bufnr)
  end
  if options.gutter then
    gutter.attach(bufnr)
  end
  if options.tables then
    tables.attach(bufnr)
  end
  if options.code_blocks then
    codeblocks.attach(bufnr)
  end
  if options.frontmatter then
    frontmatter.attach(bufnr)
  end
  apply_fold(bufnr, options)
  apply_conceal(bufnr, options)
  bind_keymaps(bufnr, options)
end

--- Configure mep.markdown (see mep.markdown.config.defaults) and
--- activate it for every markdown buffer, present and future.
function M.setup(opts)
  local options = config.setup(opts)

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = vim.api.nvim_create_augroup('MepMarkdown', { clear = true })

  -- Re-applied on every real `:colorscheme`/`mep.theme.apply` change
  -- too (not just once here), same reasoning as every other MepXxx
  -- group in this codebase — `mep.theme.engine.apply`'s own `hi clear`
  -- would otherwise wipe these the next time a theme is switched.
  local function apply_highlights()
    if options.headers then
      highlights.define_headers()
    end
    if options.emphasis then
      highlights.define_emphasis()
    end
    if options.tables then
      highlights.define_tables()
    end
    if options.code_blocks then
      highlights.define_code_blocks()
    end
    if options.frontmatter then
      highlights.define_frontmatter()
    end
  end
  apply_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = augroup,
    callback = apply_highlights,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = 'markdown',
    callback = function(args)
      activate_markdown_buffer(args.buf, options)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'markdown' then
      activate_markdown_buffer(bufnr, options)
    end
  end

  return options
end

--- Test/dev-only: undo the FileType/ColorScheme autocmds and detach
--- every attached gutter/tables/codeblocks/frontmatter buffer, so a
--- fresh setup() starts clean.
function M._reset()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  gutter._reset()
  tables._reset()
  codeblocks._reset()
  frontmatter._reset()
end

return M

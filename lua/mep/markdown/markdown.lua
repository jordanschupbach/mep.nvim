--- mep's markdown visual-styling library: distinct per-level heading
--- colors, distinct bold/emphasis colors, a heading-level marker in the
--- sign column, box-drawn GFM tables, and shaded fenced-code-block
--- backgrounds. Deliberately just visual styling — markdown has no
--- outline/TODO/agenda machinery comparable to `mep.org`'s (a much
--- larger, structural org-mode implementation) to replicate.
local config = require('mep.markdown.config')
local highlights = require('mep.markdown.highlights')
local gutter = require('mep.markdown.gutter')
local tables = require('mep.markdown.tables')
local codeblocks = require('mep.markdown.codeblocks')

local M = {}
M.highlights = highlights
M.gutter = gutter
M.tables = tables
M.codeblocks = codeblocks

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
end

--- Configure mep.markdown (see mep.markdown.config.defaults for
--- highlight/headers/emphasis/gutter/gutter_symbols) and activate it
--- for every markdown buffer, present and future.
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
--- every attached gutter/tables/codeblocks buffer, so a fresh setup()
--- starts clean.
function M._reset()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  gutter._reset()
  tables._reset()
  codeblocks._reset()
end

return M

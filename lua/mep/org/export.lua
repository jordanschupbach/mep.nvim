--- org-export framework: parses a buffer (after resolving `#+INCLUDE:`
--- directives and `#+MACRO:` expansion) into a flat, ordered document
--- model — `mep.org.export.ascii`/`.markdown`/`.html` each turn that
--- model into their own output format. Pure line-pattern parsing, same
--- style as the rest of mep.org; no tree-sitter needed.
---
--- **Scope note**: the document model is deliberately flat (a sequence
--- of headline/paragraph/list_item/src/block elements, each carrying its
--- own `level`/`depth` where relevant) rather than a nested tree of
--- sections — each backend reconstructs nesting from that as it emits
--- output (a counter stack for `num:t` numbering, an indent/list-nesting
--- stack for lists). This mirrors how the rest of mep.org already
--- represents structure (mep.org.agenda's `collect_entries` is a flat
--- list of headline entries, not a tree) and keeps the parser itself
--- simple, at the cost of backends doing their own light bookkeeping to
--- reconstruct hierarchy.
---
--- Real org tables aren't part of this model at all — not asked for by
--- ORGMODE_ROADMAP.md's Phase 11 scope, and a `|`-delimited table line
--- simply falls through to being treated as ordinary paragraph text.
local headline_mod = require('mep.org.headline')
local outline_mod = require('mep.org.outline')
local list_mod = require('mep.org.list')
local plan_mod = require('mep.org.plan')
local block_mod = require('mep.org.block')
local macro_mod = require('mep.org.macro')
local include_mod = require('mep.org.include')
local footnote_mod = require('mep.org.footnote')
local link_mod = require('mep.org.link')
local property_mod = require('mep.org.property')

local M = {}

--- Backend modules, keyed by name, and the file extension
--- `default_path` picks for each. Required lazily (inside the functions
--- below, not at module load time) since each backend itself requires
--- this module back (for `tokenize_inline`/`truthy_option`) — a
--- top-level require here would deadlock on that cycle, since Lua's
--- `require` returns an incomplete (`true`, not the module table) result
--- for a module that's still in the middle of loading itself. The same
--- "require the heavier dependency lazily, inside the function that
--- needs it" pattern mep.org.org's `apply_highlight` already uses for
--- mep.treesitter.
local BACKEND_MODULE = {
  ascii = 'mep.org.export.ascii',
  markdown = 'mep.org.export.markdown',
  html = 'mep.org.export.html',
}
local BACKEND_EXT = {
  ascii = '.txt',
  markdown = '.md',
  html = '.html',
}
M.backend_names = { 'ascii', 'markdown', 'html' }

--- Parse a `#+OPTIONS: toc:nil num:t ...` line's tail into `{ key =
--- "value", ... }` (raw strings — callers interpret `"nil"`/`"t"` etc.
--- themselves; see `truthy_option`).
local function parse_options_line(tail)
  local opts = {}
  for key, value in tail:gmatch('(%S-):(%S+)') do
    opts[key] = value
  end
  return opts
end

--- Whether `doc.options[key]` should be treated as "on", given
--- `default` (used when the key is absent). Only `"nil"` and `"no"`
--- count as off — matching real `#+OPTIONS:`'s own `nil`-means-false
--- convention.
local function truthy_option(doc, key, default)
  local raw = doc.options[key]
  if raw == nil then
    return default
  end
  return raw ~= 'nil' and raw ~= 'no'
end
M.truthy_option = truthy_option

local function has_tag(tags, name)
  for _, t in ipairs(tags) do
    if t == name then
      return true
    end
  end
  return false
end

--- Metadata-only first pass over `lines`: `#+TITLE:`/`#+AUTHOR:`/
--- `#+DATE:`/`#+OPTIONS:` (last one wins, matching real org-mode) plus
--- every `#+MACRO:` definition (via mep.org.macro). Needed before the
--- second, block-building pass so a macro/title use earlier in the
--- document than its own definition still resolves — real org-mode
--- documents almost always define these near the top anyway, but a
--- single whole-document scan costs nothing extra.
local function scan_metadata(lines)
  local doc = { title = nil, author = nil, date = nil, options = {} }
  for _, line in ipairs(lines) do
    local kw, val = line:match('^%s*#%+([%a_]+):%s*(.-)%s*$')
    if kw then
      local kwl = kw:lower()
      if kwl == 'title' then
        doc.title = val
      elseif kwl == 'author' then
        doc.author = val
      elseif kwl == 'date' then
        doc.date = val
      elseif kwl == 'options' then
        doc.options = parse_options_line(val)
      end
    end
  end
  doc.macros = macro_mod.parse_definitions(lines)
  return doc
end

--- Consume the contiguous run of list items (and their more-indented
--- continuation lines) starting at `lines[i]`. Returns the produced
--- `list_item` blocks and the index of the first line after the run.
--- Nesting `depth` (0-based) is derived from each item's indent width
--- via a small stack, matching real org-mode's own "indentation defines
--- nesting" rule rather than requiring a fixed indent-per-level.
local function consume_list(lines, i, expand)
  local items = {}
  local stack = {}
  while i <= #lines do
    local line = lines[i]
    local item = list_mod.parse(line)
    if item then
      local w = #item.indent
      while #stack > 0 and stack[#stack] > w do
        table.remove(stack)
      end
      if #stack == 0 or stack[#stack] < w then
        stack[#stack + 1] = w
      end
      local depth = #stack - 1
      local content = item.content
      local mark, rest = content:match('^%[([ xX])%]%s*(.*)$')
      local checkbox = nil
      if mark then
        checkbox = mark ~= ' '
        content = rest
      end
      items[#items + 1] = { type = 'list_item', depth = depth, ordered = item.kind == 'ordered', checkbox = checkbox, text = expand(content) }
      i = i + 1
    elseif line ~= '' and #(line:match('^(%s*)')) > (stack[#stack] or 0) and #items > 0 then
      items[#items].text = items[#items].text .. ' ' .. expand(line:match('^%s*(.-)%s*$'))
      i = i + 1
    else
      break
    end
  end
  return items, i
end

--- Build the flat, ordered `blocks` list for `lines` given already-known
--- document metadata (`doc.macros`, used to expand `{{{name}}}` in
--- paragraph/list-item/headline text and quote/verse/center block bodies
--- — real org-mode doesn't macro-expand literal `src`/`example` content,
--- and neither does this). A headline tagged `:noexport:` (real
--- org-mode's default `org-export-exclude-tags`) is skipped along with
--- its entire subtree. Also returns `footnotes`, an ordered list of
--- `{ name, text }` collected from standalone `[fn:name] text` lines.
local function build_blocks(lines, todo_keywords, macros)
  local function expand(text)
    return macro_mod.expand(text, macros)
  end

  local blocks = {}
  local footnotes = {}
  local seen_footnote = {}
  local i = 1
  local skip_until_level = nil

  local block_by_start = {}
  for _, b in ipairs(block_mod.find_blocks(lines)) do
    block_by_start[b.start_lnum] = b
  end

  while i <= #lines do
    local line = lines[i]

    if skip_until_level then
      if headline_mod.is_headline(line) then
        local lvl = #(line:match('^(%*+)'))
        if lvl <= skip_until_level then
          skip_until_level = nil
        else
          i = i + 1
          goto continue
        end
      else
        i = i + 1
        goto continue
      end
    end

    if line:match('^%s*#%+') and not block_by_start[i] then
      -- document keyword line (#+TITLE:/#+MACRO:/#+OPTIONS:/etc, or an
      -- unrecognized one) — metadata is already collected by
      -- scan_metadata; none of these produce a body block. Checked
      -- against block_by_start first so a `#+begin_src`/`#+begin_quote`/
      -- etc. line (which also matches this shape) falls through to the
      -- block-handling branch below instead of being silently dropped.
      i = i + 1
      goto continue
    end

    if headline_mod.is_headline(line) then
      local parsed = headline_mod.parse(line, todo_keywords)
      if has_tag(parsed.tags, 'noexport') then
        skip_until_level = parsed.level
        i = i + 1
        goto continue
      end
      blocks[#blocks + 1] = {
        type = 'headline',
        level = parsed.level,
        todo = parsed.todo,
        priority = parsed.priority,
        title = expand(parsed.title),
        tags = parsed.tags,
      }
      i = i + 1
      goto continue
    end

    if plan_mod.is_plan_line(line) then
      i = i + 1
      goto continue
    end

    local drawer_name = line:match('^%s*:([%w_%-]+):%s*$')
    if drawer_name and drawer_name:upper() ~= 'END' then
      i = i + 1
      while lines[i] and not lines[i]:match('^%s*:[Ee][Nn][Dd]:%s*$') do
        i = i + 1
      end
      i = i + 1
      goto continue
    end

    local def_name, def_text = line:match('^%[fn:([%w_%-]+)%]%s+(.*)$')
    if def_name then
      if not seen_footnote[def_name] then
        seen_footnote[def_name] = true
        footnotes[#footnotes + 1] = { name = def_name, text = expand(def_text) }
      end
      i = i + 1
      goto continue
    end

    local blk = block_by_start[i]
    if blk then
      if blk.kind == 'src' then
        local lang = (blk.args or ''):match('^(%S*)') or ''
        blocks[#blocks + 1] = { type = 'src', lang = lang, body = blk.body }
      elseif blk.kind == 'quote' or blk.kind == 'verse' or blk.kind == 'center' then
        local body = {}
        for _, l in ipairs(blk.body) do
          body[#body + 1] = expand(l)
        end
        blocks[#blocks + 1] = { type = 'block', kind = blk.kind, body = body }
      elseif blk.kind ~= 'comment' then
        -- example, or any other block kind: passthrough, no macro expansion
        blocks[#blocks + 1] = { type = 'block', kind = blk.kind, body = blk.body }
      end
      i = blk.end_lnum + 1
      goto continue
    end

    if line:match('^%s*#%s') or line:match('^%s*#$') then
      i = i + 1
      goto continue
    end

    if list_mod.is_list_item(line) then
      local items, next_i = consume_list(lines, i, expand)
      vim.list_extend(blocks, items)
      i = next_i
      goto continue
    end

    if line:match('^%s*$') then
      i = i + 1
      goto continue
    end

    do
      local para_lines = {}
      while
        lines[i]
        and not lines[i]:match('^%s*$')
        and not headline_mod.is_headline(lines[i])
        and not list_mod.is_list_item(lines[i])
        and not block_by_start[i]
        and not lines[i]:match('^%[fn:[%w_%-]+%]%s+')
        and not lines[i]:match('^%s*#%+')
        and not plan_mod.is_plan_line(lines[i])
        and not lines[i]:match('^%s*:[%w_%-]+:%s*$')
        and not lines[i]:match('^%s*#%s')
        and not lines[i]:match('^%s*#$')
      do
        para_lines[#para_lines + 1] = expand(lines[i])
        i = i + 1
      end
      blocks[#blocks + 1] = { type = 'paragraph', lines = para_lines }
    end

    ::continue::
  end

  return blocks, footnotes
end

--- Assign `number` ("1", "1.2", ...) to every `headline` block in
--- `blocks`, in place, real org-mode's default `num:t` numbering. A
--- level deeper than the previous headline's by more than one still
--- gets a coherent number (its skipped intermediate counters implicitly
--- start at 1), matching how a document with an irregular level jump
--- still numbers sensibly.
local function number_headlines(blocks)
  local counters = {}
  for _, b in ipairs(blocks) do
    if b.type == 'headline' then
      for l = #counters, b.level + 1, -1 do
        counters[l] = nil
      end
      counters[b.level] = (counters[b.level] or 0) + 1
      local parts = {}
      for l = 1, b.level do
        parts[#parts + 1] = tostring(counters[l] or 1)
      end
      b.number = table.concat(parts, '.')
    end
  end
end

--- Parse `lines` (already include-resolved, if desired) into a document:
--- `{ title, author, date, options, blocks, footnotes }`. `opts.
--- todo_keywords` matches the rest of mep.org (default `{}`).
function M.parse_lines(lines, opts)
  opts = opts or {}
  local doc = scan_metadata(lines)
  local blocks, footnotes = build_blocks(lines, opts.todo_keywords or {}, doc.macros)
  if truthy_option(doc, 'num', true) then
    number_headlines(blocks)
  end
  doc.blocks = blocks
  doc.footnotes = footnotes
  doc.macros = nil
  return doc
end

--- Parse `bufnr` into a document (see `parse_lines`). `#+INCLUDE:`
--- directives are resolved first (relative to the buffer's own file
--- directory) unless `opts.resolve_includes == false`.
function M.parse(bufnr, opts)
  opts = opts or {}
  local lines
  if opts.resolve_includes == false then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    lines = include_mod.resolve(bufnr)
  end
  return M.parse_lines(lines, opts)
end

--- Tokenize `text` (already macro-expanded, from a paragraph, list item,
--- or headline title) into an ordered list of inline tokens for a
--- backend to render: `{ type = 'text', text }`, `{ type = 'bold'|
--- 'italic'|'underline'|'strike'|'code'|'verbatim', text }`, `{ type =
--- 'link', target, description }`, `{ type = 'footnote', name, def }`
--- (`name` nil for an anonymous inline definition, `def` nil for a
--- plain reference).
---
--- Emphasis matching is a documented simplification of real org-mode's
--- fuller border-character rules: a marker's content must not start
--- with whitespace or the marker character itself, and may not contain
--- the marker character again before the next one closes it. This
--- covers ordinary prose well (`*bold*`, `5 * 3` left alone since there's
--- no non-space char immediately after the first `*`) without
--- implementing org's full pre/post boundary-character table.
local EMPHASIS = {
  { marker = '*', type = 'bold' },
  { marker = '/', type = 'italic' },
  { marker = '_', type = 'underline' },
  { marker = '+', type = 'strike' },
  { marker = '~', type = 'code' },
  { marker = '=', type = 'verbatim' },
}

local function emphasis_pattern(marker)
  local esc = marker:gsub('(%p)', '%%%1')
  return esc .. '([^' .. esc .. '%s][^' .. esc .. ']-)' .. esc
end

function M.tokenize_inline(text)
  local tokens = {}
  local pos = 1
  local n = #text

  while pos <= n do
    local best_s, best_e, best_token

    local ls, le, ltarget, ldesc = link_mod.find(text, pos)
    if ls and (not best_s or ls < best_s) then
      best_s, best_e, best_token = ls, le, { type = 'link', target = ltarget, description = ldesc }
    end

    local fs, fe, fname, fdef = footnote_mod.find(text, pos)
    if fs and (not best_s or fs < best_s) then
      best_s, best_e, best_token = fs, fe, { type = 'footnote', name = fname, def = fdef }
    end

    for _, e in ipairs(EMPHASIS) do
      local s, e_, content = text:find(emphasis_pattern(e.marker), pos)
      if s and (not best_s or s < best_s) then
        best_s, best_e, best_token = s, e_, { type = e.type, text = content }
      end
    end

    if not best_s then
      tokens[#tokens + 1] = { type = 'text', text = text:sub(pos) }
      break
    end
    if best_s > pos then
      tokens[#tokens + 1] = { type = 'text', text = text:sub(pos, best_s - 1) }
    end
    tokens[#tokens + 1] = best_token
    pos = best_e + 1
  end

  return tokens
end

--- Render `doc` (from `parse`/`parse_lines`) via the named backend
--- (`'ascii'`/`'markdown'`/`'html'`): a list of output lines.
function M.render(doc, backend_name)
  local modname = BACKEND_MODULE[backend_name]
  if not modname then
    error('mep.org.export: unknown backend "' .. tostring(backend_name) .. '"')
  end
  return require(modname).render(doc)
end

--- The buffer's own file directory (falling back to the cwd for an
--- unsaved buffer) — shared by `parse`'s include-resolution and
--- `default_path`/`export_subtree`'s output-path resolution.
local function buffer_dir(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return bufname ~= '' and vim.fn.fnamemodify(bufname, ':h') or vim.fn.getcwd()
end

--- The default export target path for `bufnr` under `backend_name`:
--- same directory and basename as the buffer's file, with the backend's
--- own extension (`.txt`/`.md`/`.html`) — real org-export's own
--- "export next to the source file" convention. nil for an unsaved
--- buffer (no basename to derive from) or an unknown backend.
function M.default_path(bufnr, backend_name)
  local ext = BACKEND_EXT[backend_name]
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if not ext or bufname == '' then
    return nil
  end
  return vim.fn.fnamemodify(bufname, ':r') .. ext
end

--- Render `doc` via `backend_name` and write it to `path` (overwriting
--- any existing content). Returns `path`.
function M.write(doc, backend_name, path)
  vim.fn.writefile(M.render(doc, backend_name), path)
  return path
end

--- Parse `bufnr` and export it via `backend_name` to `path` (default:
--- `default_path`). Returns the written path, or nil (with a
--- notification) if no path was given/derivable.
function M.export_to_file(bufnr, backend_name, path, opts)
  path = path or M.default_path(bufnr, backend_name)
  if not path then
    vim.notify('mep.org: no export path (buffer has no file name)', vim.log.levels.WARN)
    return nil
  end
  local doc = M.parse(bufnr, opts)
  return M.write(doc, backend_name, path)
end

--- Export just the subtree rooted at the headline containing `lnum` —
--- real org-mode's per-subtree export. The root headline's own title
--- becomes the document title (its `:EXPORT_TITLE:` property overrides
--- this, if set — real org-mode's own subtree-export property); its
--- descendants' levels are renormalized so the first child level becomes
--- level 1, matching real org-mode's own subtree-export behavior of
--- treating the subtree as a standalone document rather than preserving
--- its original absolute depth. Returns the written path, or nil (with
--- a notification) if `lnum` isn't inside a headline or no path was
--- given/derivable.
function M.export_subtree(bufnr, lnum, backend_name, path, opts)
  opts = opts or {}
  local todo_keywords = opts.todo_keywords or {}
  local at = outline_mod.current_headline(bufnr, lnum)
  if not at then
    vim.notify('mep.org: no headline at cursor to export', vim.log.levels.WARN)
    return nil
  end
  path = path or M.default_path(bufnr, backend_name)
  if not path then
    vim.notify('mep.org: no export path (buffer has no file name)', vim.log.levels.WARN)
    return nil
  end

  local last = outline_mod.subtree_end(bufnr, at)
  local root_line = vim.api.nvim_buf_get_lines(bufnr, at - 1, at, false)[1]
  local root_level = #(root_line:match('^(%*+)'))
  local export_title = property_mod.get(bufnr, at, 'EXPORT_TITLE') or headline_mod.parse(root_line, todo_keywords).title

  local body_lines = at < last and vim.api.nvim_buf_get_lines(bufnr, at, last, false) or {}
  local normalized = { '#+TITLE: ' .. export_title }
  for _, line in ipairs(body_lines) do
    local stars, rest = line:match('^(%*+)(.*)$')
    if stars then
      normalized[#normalized + 1] = string.rep('*', math.max(1, #stars - root_level)) .. rest
    else
      normalized[#normalized + 1] = line
    end
  end

  if opts.resolve_includes ~= false then
    normalized = include_mod.resolve_lines(normalized, buffer_dir(bufnr))
  end
  local doc = M.parse_lines(normalized, opts)
  return M.write(doc, backend_name, path)
end

--- Export the current buffer (or, with `opts.subtree_lnum` set, just the
--- subtree at that line — see `export_subtree`) interactively: prompts
--- for a backend via `vim.ui.select` (real org-export-dispatch's own
--- "ask a backend first" UX, simplified from its fuller menu of
--- backend/scope/async combinations), then writes to `default_path` and
--- notifies where.
function M.dispatch_interactive(bufnr, opts)
  opts = opts or {}
  vim.ui.select(M.backend_names, { prompt = 'Export backend:' }, function(choice)
    if not choice then
      return
    end
    local path
    if opts.subtree_lnum then
      path = M.export_subtree(bufnr, opts.subtree_lnum, choice, nil, opts)
    else
      path = M.export_to_file(bufnr, choice, nil, opts)
    end
    if path then
      vim.notify('mep.org: exported to ' .. path, vim.log.levels.INFO)
    end
  end)
end

return M

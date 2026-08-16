--- "Poly mode" for org buffers: real LSP features (hover, go-to-
--- definition, references, rename, diagnostics, completion) sourced from
--- each embedded language's own server while the cursor is inside a
--- `#+begin_src <lang> ... #+end_src` block — syntax highlighting for the
--- same blocks is a separate, simpler mechanism (`queries/org/
--- injections.scm`'s tree-sitter language injection, active automatically
--- whenever org highlighting itself is, no wiring here).
---
--- The trick (the same one otter.nvim popularized, reimplemented here
--- with zero dependencies): for each language a buffer's src blocks use,
--- keep one hidden real Neovim buffer (a "shadow buffer") in sync with
--- that language's block bodies, laid out at *the same line numbers* as
--- the org buffer — every line outside a block of that language is left
--- blank. A src block's own body already has no other indentation
--- convention to preserve, so this keeps every position (line *and*
--- column) identical between the org buffer and its shadow buffers,
--- which means bridging a request is just "ask the shadow buffer's own
--- attached client about the real cursor position" — no coordinate
--- translation code needed at all, only URI rewriting (shadow buffer's
--- fake path -> the real org file) on the way back for anything that
--- returns a location.
---
--- The shadow buffer's `filetype` is set to the target language's own
--- Neovim filetype (mep.org.lang.to_filetype) and nothing else — no
--- client is ever started directly by this module. Whatever server(s)
--- mep.lsp (or your own LSP config) already registered via `vim.lsp.
--- enable` for that filetype attach on their own, through Neovim's normal
--- `FileType` autostart, the moment the shadow buffer's filetype is set;
--- Neovim's own buffer-change tracking then keeps that client's view of
--- the shadow buffer's text current automatically, the same as any real
--- edited buffer, whenever `sync` rewrites its lines.
---
--- A given language's shadow buffer is only ever created the first time
--- the cursor actually lands inside one of its blocks (`context_at_cursor`
--- creates it lazily on demand) — *not* proactively for every language
--- `sync` sees in the buffer. Since creating one is exactly what triggers
--- real-server autostart above, eager creation would silently start (and
--- let attach) a real language server for every src-block language the
--- instant an org buffer is opened, whether or not the user ever visits
--- that block — confirmed the hard way: a demo org file with a `d`
--- example block, opened on a machine that happens to have `serve-d` on
--- `PATH`, silently started it and popped up its own "DCD is out of
--- date, download it?" prompt before the cursor had moved once. `sync`
--- itself only ever *refreshes* shadow buffers that already exist.
---
--- A shadow buffer's own content is otherwise never written to real
--- disk (see `get_or_create_shadow`'s own comment for how that's
--- enforced despite needing `buftype=''`) — except for `MANIFESTS`
--- (below)-listed languages, where it's unavoidable: `vim.lsp.enable`
--- attaching a client is necessary but not sufficient for those, since
--- their servers separately validate an on-disk project structure
--- through their own build tooling (confirmed empirically: rust-analyzer
--- literally shells out to `cargo check`), independent of whatever
--- Neovim's client has told them about the buffer's live content.
local babel = require('mep.org.babel')
local lang = require('mep.org.lang')

local M = {}

-- Forward declaration: get_or_create_shadow (below) registers a
-- diagnostics-mirroring autocmd per shadow buffer, whose callback is this
-- function, defined further down.
local refresh_diagnostics

-- bufnr (org buffer) -> { shadow = {[filetype] = shadow_bufnr},
-- shadow_paths = {[filetype] = path}, diag_ns, last_status_ft,
-- scaffold_root }. `last_status_ft` is `status_widget()`'s own
-- redraw-dedup state (see `setup_buffer`'s CursorMoved autocmd).
-- `scaffold_root` is the `.mep-polyglot/<bufnr>` directory `shadow_path`
-- computes shadow buffer paths (and any MANIFESTS scaffold file) under —
-- cached once, at setup time, rather than recomputed from the org
-- buffer's own name at every call, so cleanup still works after that
-- buffer is no longer valid (`teardown_buffer` runs on `BufWipeout`).
-- `shadow_paths` is `M.sync`'s own record of each language's on-disk
-- path, needed only for the `MANIFESTS`-listed ones it mirrors real
-- content to (see `M.sync`'s own comment for why).
local state = {}
-- shadow bufnr -> owning org bufnr, module-level (shared across every org
-- buffer this module manages) so a jump/rename result landing on some
-- *other* org buffer's shadow doc still resolves correctly.
local shadow_owner = {}

--- Installs (in the background, via `mep.treesitter.install` — a no-op
--- for anything already available anywhere on `runtimepath`) the
--- tree-sitter parser for every distinct language `bufnr`'s src blocks
--- use, so `queries/org/injections.scm`'s highlighting actually has
--- something to inject. Needed because `mep.treesitter`'s own
--- `ensure_installed` only ever installs its curated registry as a whole
--- (or an explicit subset) — it has no idea an *org* buffer's src blocks
--- are about to need `ruby`/`rust`/`go`/etc, and `ensure_installed =
--- false` (e.g. `scripts/try_init.lua`'s own "too heavy for a quick
--- session" tradeoff) skips that whole-registry install entirely. Calls
--- `on_installed(ts_lang)` once per language that successfully becomes
--- available; never for one with no curated registry entry (`perl`, `r`
--- — not installable this way at all) or a failed install (no compiler/
--- git on PATH) — same graceful-miss contract as everywhere else this
--- project touches tree-sitter.
function M.ensure_language_parsers(bufnr, on_installed)
  local install = require('mep.treesitter.install')
  local seen = {}
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    local ts_lang = lang.to_treesitter_lang(block.lang)
    if ts_lang and not seen[ts_lang] then
      seen[ts_lang] = true
      install.install(ts_lang, function(ok)
        if ok and on_installed then
          on_installed(ts_lang)
        end
      end)
    end
  end
end

--- filetype -> `{ open, close }`: a minimal synthetic wrapper for a
--- language whose block bodies, as literally written, aren't valid/
--- parseable on their own — most commonly a compiled language's bare
--- statements needing an entry-point function (real org-babel only
--- wraps these at *execution* time, `mep.org.babel`'s own per-language
--- `wrap_main`, applied by `execute`, not stored anywhere reusable
--- here), but not only that (see `php`'s own entry below). A shadow
--- buffer has no execution step, so without this a block's body would
--- otherwise be handed to its language server exactly as written.
--- Confirmed empirically against clangd on an unwrapped C block (`int x
--- = 10; printf(...)`) — it doesn't just flag the bare call, it
--- mis-parses the whole thing as an implicit-`int`-return function
--- declaration ("type specifier missing, defaults to 'int'"), which is
--- far more confusing than the plain "undeclared identifier" a real
--- syntax error would give.
---
--- Deliberately minimal, not execution-accurate: no `:includes` handling
--- for the entry-point languages (`#include`/Go's `import` are their own
--- directive lines with no legal way to share a line with `open` — C's
--- preprocessor in particular requires a directive to be alone on its
--- physical line — so a missing header still shows as its own, more
--- sensible "implicit declaration" diagnostic instead) and no support
--- for more than one wrapped block (see `babel.should_wrap_main`) of the
--- *same* entry-point language in one org file (each gets its own
--- `open`/`close`, so two would both try to define `main` in the same
--- shadow buffer — the
--- identical "only one real program at a time" constraint real
--- org-babel's own wrap-at-execution already implies, just surfaced
--- earlier here).
local ENTRY_WRAPPERS = {
  c = { open = 'int main(void) {', close = 'return 0; }' },
  cpp = { open = 'int main() {', close = 'return 0; }' },
  rust = { open = 'fn main() {', close = '}' },
  -- `;`-joined onto one line deliberately: Go requires exactly one
  -- `package` clause as the file's first declaration, which would
  -- otherwise need a *second* reserved line this module doesn't have
  -- (only the block's own `#+begin_src`/`#+end_src` lines, already
  -- blank, are free to reuse without shifting the body's own line
  -- numbers) — `package main; func main() {` parses identically to the
  -- same two statements on separate lines (Go's semicolon-insertion
  -- rules make the two forms equivalent).
  go = { open = 'package main; func main() {', close = '}' },
  -- Not an entry-point wrapper at all — PHP has no such concept — but
  -- the identical mechanism (a synthetic line on the block's own blank
  -- `#+begin_src` slot, `close` left empty since nothing needs to follow
  -- the body) fixes the same class of problem: confirmed empirically
  -- that a `.php` file with no `<?php` tag doesn't fail to highlight
  -- with some *wrong* set of captures, it doesn't parse as PHP code at
  -- all — `(program (text))`, the grammar's own "this is just static
  -- HTML" fallback — so there's no PHP syntax tree for a query to ever
  -- match against. Mirrors `mep.org.babel.languages.php`'s own
  -- `wrap_php_tags`, applied at *execution* time for the same reason.
  php = { open = '<?php', close = '' },
}

--- Every language currently in `raw_lang`'s block(s), rebuilt as
--- `#total_lines` lines: blank except where `bufnr`'s own src blocks in
--- that language put real body text, at their own original line numbers.
local function shadow_lines_for(bufnr, target_ft)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = {}
  for i = 1, total do
    lines[i] = ''
  end
  local wrapper = ENTRY_WRAPPERS[target_ft]
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    if lang.to_filetype(block.lang) == target_ft then
      for k, body_line in ipairs(block.body) do
        lines[block.start_lnum + k] = body_line
      end
      if wrapper and babel.should_wrap_main(target_ft, babel.parse_header_args(block.args)) then
        lines[block.start_lnum] = wrapper.open
        lines[block.end_lnum] = wrapper.close
      end
    end
  end
  return lines
end

--- The `.mep-polyglot/<org bufnr>` directory `shadow_path` computes every
--- shadow buffer path under, inside the org file's own directory (so LSP
--- `root_markers` like `.git` still resolve the way they would for the
--- real file) — one subdirectory per org buffer so its own scaffolding
--- never collides with another org buffer's.
local function scaffold_root(org_bufnr)
  local org_name = vim.api.nvim_buf_get_name(org_bufnr)
  local dir = org_name ~= '' and vim.fn.fnamemodify(org_name, ':h') or vim.fn.getcwd()
  return string.format('%s/.mep-polyglot/%d', dir, org_bufnr)
end

--- Directory + full path for a shadow buffer — `<scaffold_root>/<ft>/
--- shadow<ext>`, one subdirectory per language so a real on-disk
--- manifest (`MANIFESTS` below) can live alongside it without colliding
--- with any other language's own. For most languages the shadow buffer's
--- own *content* is never actually written here — see
--- `get_or_create_shadow` below for how that's enforced despite needing
--- `buftype=''` — `MANIFESTS`-listed ones are the one exception (see
--- `M.sync`'s own comment for why).
local function shadow_path(root, ft, ext)
  local dir = root .. '/' .. ft
  return dir, dir .. '/shadow' .. ext
end

--- ft -> function(shadow_basename) -> `{ filename, lines }` | nil: a
--- tiny, real, on-disk project manifest some language servers flatly
--- refuse to do anything without — confirmed empirically that both
--- rust-analyzer and gopls return a completely empty hover result for a
--- Cargo.toml-less/go.mod-less file (rust-analyzer additionally logs a
--- visible "Failed to discover workspace" error on open). Written once,
--- into the shadow buffer's own directory, the first time that directory
--- is created; removed again with it in `teardown_buffer`.
local MANIFESTS = {
  rust = function(shadow_basename)
    return {
      filename = 'Cargo.toml',
      lines = {
        '[package]',
        'name = "shadow"',
        'version = "0.0.0"',
        'edition = "2021"',
        '',
        '[[bin]]',
        'name = "shadow"',
        'path = "' .. shadow_basename .. '"',
      },
    }
  end,
  go = function()
    return {
      filename = 'go.mod',
      lines = { 'module shadow', '', 'go 1.21' },
    }
  end,
}

--- Writes `ft`'s `MANIFESTS` entry (if any) into `dir`, unless it's
--- already there (e.g. from an earlier session — never rewritten once
--- present, it's static content that never needs to change), plus a
--- blanket `.gitignore` (`*`) at `root` covering everything under it.
--- Only for `MANIFESTS`-listed languages: a no-op for anything else,
--- since a language with no entry here never gets anything written to
--- `root`/`dir` at all (see `M.sync`'s own comment) — nothing to ignore.
local function ensure_manifest(root, dir, ft, shadow_basename)
  local make = MANIFESTS[ft]
  if not make then
    return
  end
  pcall(vim.fn.mkdir, root, 'p')
  if vim.fn.filereadable(root .. '/.gitignore') == 0 then
    vim.fn.writefile({ '*' }, root .. '/.gitignore')
  end
  local manifest = make(shadow_basename)
  local path = dir .. '/' .. manifest.filename
  if vim.fn.filereadable(path) == 0 then
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(manifest.lines, path)
  end
end

local function get_or_create_shadow(org_bufnr, raw_lang)
  local ft = lang.to_filetype(raw_lang)
  if not ft then
    return nil
  end
  local st = state[org_bufnr]
  local shadow = st.shadow[ft]
  if shadow and vim.api.nvim_buf_is_valid(shadow) then
    return shadow
  end
  local dir, path = shadow_path(st.scaffold_root, ft, lang.to_extension(raw_lang))
  ensure_manifest(st.scaffold_root, dir, ft, vim.fn.fnamemodify(path, ':t'))
  st.shadow_paths[ft] = path
  shadow = vim.api.nvim_create_buf(false, true)
  -- Deliberately `buftype = ''` (a real/"normal" buffer), not the more
  -- obvious `'nofile'` — confirmed empirically (and in Neovim's own
  -- source, `lsp_enable_callback` in runtime/lua/vim/lsp.lua: "Only ever
  -- attach to buffers ... that represent an actual file") that `vim.lsp.
  -- enable`'s autostart *hard-skips any buftype other than '' or
  -- 'help'* — a 'nofile' shadow buffer would never get a client at all,
  -- regardless of anything else being right. Since a real buftype is
  -- "writable" by definition, everything below exists to make sure that
  -- writability is never actually exercised *by the user*: `modified` is
  -- forced back to `false` after every edit (`sync`, and once more right
  -- here after the initial content lands), and a `BufWriteCmd` autocmd
  -- intercepts `:w`/`:wall`/`:wa` entirely (clearing `modified` instead
  -- of writing), so `:qa`/`:wqa` never blocks on "No write since last
  -- change" because of a buffer the user never even knows exists — this
  -- is about *Vim's own* write path specifically; `M.sync` still
  -- programmatically `vim.fn.writefile`s a `MANIFESTS`-listed language's
  -- content directly (bypassing `:w`/this autocmd entirely), for reasons
  -- particular to those languages (see `M.sync`'s own comment).
  vim.bo[shadow].buftype = ''
  vim.bo[shadow].bufhidden = 'hide'
  vim.bo[shadow].swapfile = false
  vim.bo[shadow].undofile = false
  vim.bo[shadow].buflisted = false
  pcall(vim.api.nvim_buf_set_name, shadow, path)
  -- Fires FileType, which is what vim.lsp.enable's own autocmd (set up by
  -- mep.lsp.setup, or your own LSP config) listens on to auto-attach.
  vim.bo[shadow].filetype = ft
  vim.bo[shadow].modified = false
  st.shadow[ft] = shadow
  shadow_owner[shadow] = org_bufnr
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = shadow,
    callback = function()
      vim.bo[shadow].modified = false
    end,
  })
  -- Buffer-scoped to the shadow buffer itself (auto-cleaned up when it's
  -- deleted, unlike a single global-scope autocmd that would otherwise
  -- accumulate one dead closure per org buffer for the lifetime of the
  -- Neovim session).
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    buffer = shadow,
    callback = function()
      refresh_diagnostics(org_bufnr)
    end,
  })
  return shadow
end

--- Rewrites the content of every shadow buffer already tracked for
--- `bufnr` (including one whose language no longer appears in the buffer
--- — left all-blank rather than deleted, so a language removed and then
--- re-added in the same editing session doesn't repeatedly tear down and
--- reattach a client) from its current src blocks. Deliberately never
--- creates a *new* shadow buffer for a language sync sees but hasn't
--- tracked yet — see this module's own header comment for why that's
--- `context_at_cursor`'s job, lazily, instead.
function M.sync(bufnr)
  local st = state[bufnr]
  if not st then
    return
  end
  for ft, shadow in pairs(st.shadow) do
    if vim.api.nvim_buf_is_valid(shadow) then
      local lines = shadow_lines_for(bufnr, ft)
      if not vim.deep_equal(vim.api.nvim_buf_get_lines(shadow, 0, -1, false), lines) then
        vim.api.nvim_buf_set_lines(shadow, 0, -1, false, lines)
        -- buftype='' (required for LSP autostart to consider this buffer
        -- at all — see get_or_create_shadow) means this edit just set
        -- 'modified'; force it back off so this fake, never-saved buffer
        -- never blocks :qa/:wqa with "No write since last change".
        vim.bo[shadow].modified = false
        -- MANIFESTS-listed languages (rust, go) get their content
        -- mirrored to real disk too, the one exception to "a shadow
        -- buffer's content never touches disk" — confirmed empirically
        -- that this is unavoidable for them specifically: their
        -- MANIFESTS scaffold makes `vim.lsp.enable` and rust-analyzer/
        -- gopls agree a real project exists here at all, but a build-
        -- system-backed workspace load (`cargo check` for rust-analyzer;
        -- confirmed via a literal `error: can't find bin ... at path`)
        -- still separately validates that path *on disk*, independent of
        -- anything Neovim's LSP client has told it about the open
        -- buffer's own in-memory content. `ensure_manifest` already
        -- wrote a blanket `.gitignore` (`*`) into this org buffer's own
        -- scaffold_root, so this never leaks into the user's own repo.
        if MANIFESTS[ft] and st.shadow_paths[ft] then
          pcall(vim.fn.writefile, lines, st.shadow_paths[ft])
        end
      end
    end
  end
end

--- `{ shadow_bufnr, ft, block }` for the src block containing `lnum` in
--- `bufnr`, or nil if `lnum` isn't strictly inside one (on the
--- `#+begin_src`/`#+end_src` delimiter line itself doesn't count — those
--- lines are blank in every shadow buffer) or the language has no
--- Neovim filetype mapping (mep.org.lang.to_filetype). Lazily creates
--- (and immediately populates) that block's language's shadow buffer the
--- first time it's asked about — see this module's own header comment
--- for why that's deliberately not done any earlier/more eagerly than
--- this.
function M.context_at_cursor(bufnr, lnum)
  local block = babel.at_cursor(bufnr, lnum)
  if not block or lnum <= block.start_lnum or lnum >= block.end_lnum then
    return nil
  end
  local st = state[bufnr]
  if not st then
    return nil
  end
  local ft = lang.to_filetype(block.lang)
  if not ft then
    return nil
  end
  local shadow = st.shadow[ft]
  if not shadow or not vim.api.nvim_buf_is_valid(shadow) then
    shadow = get_or_create_shadow(bufnr, block.lang)
    if not shadow then
      return nil
    end
    M.sync(bufnr)
  end
  return { shadow_bufnr = shadow, ft = ft, block = block }
end

local function clients_for(shadow_bufnr, method)
  return vim.lsp.get_clients({ bufnr = shadow_bufnr, method = method })
end

--- `vim.lsp.util.make_position_params`, computed against the real cursor
--- (so multi-byte columns on this exact line convert correctly) but
--- pointed at the shadow buffer's URI — safe because a src block's body
--- line is copied into its shadow buffer completely unmodified, so the
--- two are byte-for-byte identical at this line.
local function position_params(shadow_bufnr, client)
  local win = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  params.textDocument.uri = vim.uri_from_bufnr(shadow_bufnr)
  return params
end

--- Rewrites a shadow buffer's URI back to its owning org buffer's — a
--- jump/reference/rename result landing back inside the same src block
--- (or another block of the same language, or even a block in a
--- *different* open org buffer this module also tracks) should land the
--- user in the real org file they're editing, never in a hidden shadow
--- buffer.
local function translate_uri(uri)
  local ok, buf = pcall(vim.uri_to_bufnr, uri)
  if not ok then
    return uri
  end
  local owner = shadow_owner[buf]
  return owner and vim.uri_from_bufnr(owner) or uri
end

local function translate_locations(result)
  if result == nil then
    return result
  end
  local is_single = result.uri ~= nil or result.targetUri ~= nil
  local list = is_single and { result } or result
  for _, item in ipairs(list) do
    if item.uri then
      item.uri = translate_uri(item.uri)
    end
    if item.targetUri then
      item.targetUri = translate_uri(item.targetUri)
    end
  end
  return is_single and list[1] or list
end

local function translate_workspace_edit(edit)
  if not edit then
    return edit
  end
  if edit.changes then
    local translated = {}
    for uri, edits in pairs(edit.changes) do
      translated[translate_uri(uri)] = edits
    end
    edit.changes = translated
  end
  if edit.documentChanges then
    for _, change in ipairs(edit.documentChanges) do
      if change.textDocument and change.textDocument.uri then
        change.textDocument.uri = translate_uri(change.textDocument.uri)
      end
    end
  end
  return edit
end

--- Sends `method` to the first client attached to the shadow buffer for
--- the src block at `bufnr`'s cursor, running its response through
--- `translate` (if given) before handing it to Neovim's own default
--- handler for `method` — same display/jump/quickfix behavior a real
--- attached client would get, just re-targeted at the org buffer. Falls
--- back to `vim.lsp.buf[fallback_name]` (whatever's attached to the org
--- buffer itself, ordinarily nothing) when the cursor isn't inside a src
--- block at all — real org-mode LSPs, if any, still get a chance outside
--- of code.
local function bridge(method, fallback_name, translate, extra_params)
  return function()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local ctx = M.context_at_cursor(bufnr, lnum)
    if not ctx then
      return vim.lsp.buf[fallback_name]()
    end
    local clients = clients_for(ctx.shadow_bufnr, method)
    if #clients == 0 then
      vim.notify(string.format('mep.org.polyglot: no %s language server attached', ctx.ft), vim.log.levels.WARN)
      return
    end
    local client = clients[1]
    local params = position_params(ctx.shadow_bufnr, client)
    if extra_params then
      params = vim.tbl_extend('force', params, extra_params())
    end
    client:request(method, params, function(err, result, rctx, rconfig)
      if translate then
        result = translate(result)
      end
      local handler = vim.lsp.handlers[method]
      if handler then
        handler(err, result, vim.tbl_extend('force', rctx, { bufnr = bufnr }), rconfig)
      end
    end, ctx.shadow_bufnr)
  end
end

--- `omnifunc` (`:help complete-functions`) for an org buffer: manual
--- (`<C-x><C-o>`) completion sourced from the src block at the cursor's
--- own shadow buffer, via `vim.fn.complete()` — deliberately not
--- autotrigger-as-you-type like `mep.lsp`'s own `vim.lsp.completion.
--- enable` (that API attaches to a *specific* client+bufnr pair, and the
--- org buffer itself never has one); asking for completion explicitly is
--- otter.nvim's own tradeoff for the same reason.
function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local start = col
    while start > 0 and line:sub(start, start):match('[%w_]') do
      start = start - 1
    end
    M._omni_start = start
    return start
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local ctx = M.context_at_cursor(bufnr, lnum)
  if not ctx then
    return -3
  end
  local clients = clients_for(ctx.shadow_bufnr, 'textDocument/completion')
  if #clients == 0 then
    return -3
  end
  local client = clients[1]
  local params = position_params(ctx.shadow_bufnr, client)
  -- Snapshotted now, not re-read as `M._omni_start` inside the async
  -- callback below: `omnifunc` is one shared `v:lua` function reused by
  -- every org buffer, so a second completion started (in this or another
  -- buffer) before this request's response arrives would otherwise have
  -- already overwritten it.
  local start_col = M._omni_start or 0
  client:request('textDocument/completion', params, function(err, result)
    local items = (not err and result) and (result.items or result) or {}
    local words = {}
    for _, item in ipairs(items) do
      local doc = item.documentation
      words[#words + 1] = {
        word = item.insertText or item.label,
        abbr = item.label,
        menu = item.detail or '',
        info = type(doc) == 'table' and (doc.value or '') or (doc or ''),
      }
    end
    vim.fn.complete(start_col + 1, words)
  end, ctx.shadow_bufnr)
  return -2
end

--- Whether `diag` (a `vim.diagnostic.get` entry, 0-indexed `lnum`) falls
--- strictly inside one of `ranges` (1-indexed `{start_lnum, end_lnum}`
--- delimiter-line pairs, `find_blocks`'s own shape) — i.e. on an actual
--- body line of that language's block(s), not on one of `shadow_lines_for`'s
--- blank filler lines. A linter that reasons about the *whole* shadow
--- "file" (confirmed empirically: R's `languageserver`/lintr flags
--- "Remove trailing blank lines" against the hundreds of blank filler
--- lines below a one-line R block) would otherwise land its diagnostic at
--- that blank line's position — which, once mirrored onto the org buffer,
--- is wherever some *other* language's block happens to sit at that same
--- line number, nowhere near the R code it's actually about.
local function diagnostic_in_ranges(diag, ranges)
  local lnum = diag.lnum + 1
  for _, range in ipairs(ranges) do
    if lnum > range.start_lnum and lnum < range.end_lnum then
      return true
    end
  end
  return false
end

function refresh_diagnostics(bufnr)
  local st = state[bufnr]
  -- `bufnr` can still have tracked state but no longer be a real buffer:
  -- this runs off a shadow buffer's own `DiagnosticChanged` (e.g. a
  -- server's publishDiagnostics notification arriving asynchronously,
  -- on its own schedule), which can land after `bufnr` itself is
  -- deleted but before its own deferred `teardown_buffer` (BufDelete/
  -- BufWipeout schedule a tick out — see setup_buffer's own comment on
  -- why) has actually run and cleared `state[bufnr]`.
  if not st or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local ranges_by_ft = {}
  for _, block in ipairs(babel.find_blocks(bufnr)) do
    local ft = lang.to_filetype(block.lang)
    if ft and st.shadow[ft] then
      ranges_by_ft[ft] = ranges_by_ft[ft] or {}
      table.insert(ranges_by_ft[ft], block)
    end
  end
  local all = {}
  for ft, shadow in pairs(st.shadow) do
    if vim.api.nvim_buf_is_valid(shadow) then
      for _, diag in ipairs(vim.diagnostic.get(shadow)) do
        if diagnostic_in_ranges(diag, ranges_by_ft[ft] or {}) then
          all[#all + 1] = diag
        end
      end
    end
  end
  vim.diagnostic.set(st.diag_ns, bufnr, all)
end

local function bind_keymaps(bufnr, keymaps)
  local map_opts = { buffer = bufnr, silent = true, nowait = true }
  local function map_all(mode, lhs_list, fn, desc)
    local opts = vim.tbl_extend('force', map_opts, { desc = desc })
    for _, lhs in ipairs(lhs_list or {}) do
      vim.keymap.set(mode, lhs, fn, opts)
    end
  end

  map_all('n', keymaps.goto_definition, bridge('textDocument/definition', 'definition', translate_locations), 'polyglot: goto definition')
  map_all('n', keymaps.goto_declaration, bridge('textDocument/declaration', 'declaration', translate_locations), 'polyglot: goto declaration')
  map_all('n', keymaps.references, bridge('textDocument/references', 'references', translate_locations, function()
    return { context = { includeDeclaration = true } }
  end), 'polyglot: references')
  map_all('n', keymaps.implementation, bridge('textDocument/implementation', 'implementation', translate_locations), 'polyglot: goto implementation')
  map_all('n', keymaps.type_definition, bridge('textDocument/typeDefinition', 'type_definition', translate_locations), 'polyglot: goto type definition')
  map_all('n', keymaps.hover, bridge('textDocument/hover', 'hover'), 'polyglot: hover')
  map_all({ 'n', 'i' }, keymaps.signature_help, bridge('textDocument/signatureHelp', 'signature_help'), 'polyglot: signature help')
  map_all('n', keymaps.rename, function()
    local ctx = M.context_at_cursor(bufnr, vim.api.nvim_win_get_cursor(0)[1])
    if not ctx then
      return vim.lsp.buf.rename()
    end
    vim.ui.input({ prompt = 'New Name: ' }, function(new_name)
      if not new_name or new_name == '' then
        return
      end
      bridge('textDocument/rename', 'rename', translate_workspace_edit, function()
        return { newName = new_name }
      end)()
    end)
  end, 'polyglot: rename')
  map_all('n', keymaps.diagnostic_prev, vim.diagnostic.goto_prev, 'polyglot: previous diagnostic')
  map_all('n', keymaps.diagnostic_next, vim.diagnostic.goto_next, 'polyglot: next diagnostic')
  map_all('n', keymaps.diagnostic_prev_error, function()
    vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR })
  end, 'polyglot: previous error')
  map_all('n', keymaps.diagnostic_next_error, function()
    vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR })
  end, 'polyglot: next error')
  map_all('n', keymaps.diagnostic_float, vim.diagnostic.open_float, 'polyglot: show diagnostic')
end

--- Tears down everything this module tracks for `bufnr`: deletes its
--- shadow buffers (which detaches whatever client was attached to them,
--- and — since each carries its own buffer-scoped DiagnosticChanged
--- autocmd — that autocmd too) and clears its mirrored diagnostics.
--- `bufnr`'s own sync/cleanup autocmds are buffer-scoped as well, so they
--- likewise vanish on their own once `bufnr` itself is wiped; nothing
--- else here needs explicit autocmd cleanup.
function M.teardown_buffer(bufnr)
  local st = state[bufnr]
  if not st then
    return
  end
  for _, shadow in pairs(st.shadow) do
    shadow_owner[shadow] = nil
    if vim.api.nvim_buf_is_valid(shadow) then
      -- A shadow buffer's own filetype (mep.treesitter's own generic
      -- FileType activation, if that library is set up, starts real
      -- highlighting on it same as any other buffer of that filetype) can
      -- leave a tree-sitter parser/highlighter attached; deleting the
      -- buffer out from under an active one is unsafe, so stop it first —
      -- the same defensive ordering mep.org/mep.treesitter's own specs
      -- already require (see spec/README.md).
      pcall(vim.treesitter.stop, shadow)
      pcall(vim.api.nvim_buf_delete, shadow, { force = true })
    end
  end
  pcall(vim.diagnostic.reset, st.diag_ns, bufnr)
  -- Removes any MANIFESTS scaffold file(s) get_or_create_shadow wrote —
  -- the only thing this module ever puts on real disk.
  if st.scaffold_root then
    pcall(vim.fn.delete, st.scaffold_root, 'rf')
  end
  state[bufnr] = nil
end

-- Created lazily, once, the first time any buffer is set up — deliberately
-- *not* mep.org.org's own per-`setup()` `MepOrg` group: that one is
-- recreated (`clear = true`) on every `mep.org.setup()` call so changed
-- options take effect, but `mep.org.setup()` also re-activates every
-- already-loaded org buffer on each call, which would mean re-registering
-- (and, worse, transiently *dropping*, between the old group's deletion
-- and the new one's autocmds landing) every open buffer's sync/diagnostic/
-- cleanup autocmds on every single `setup()` call — real, avoidable cost
-- with many org buffers open. A stable, buffer-scoped group sidesteps
-- this: each buffer's own autocmds are registered exactly once (guarded
-- by `state[bufnr]` below) and never need to move.
local augroup = nil
local function ensure_augroup()
  if not augroup then
    augroup = vim.api.nvim_create_augroup('MepOrgPolyglot', { clear = true })
  end
  return augroup
end

--- Activates (or tears down, if `opts` is falsy) poly-mode LSP bridging
--- for org buffer `bufnr`. `opts` is `mep.org.config.defaults.polyglot`'s
--- own shape: `{ keymaps = {...} }`. Safe to call repeatedly for the same
--- buffer (`mep.org.setup()` does, once per already-open org buffer, on
--- every call) — content re-syncs and keymaps/omnifunc re-bind every
--- time (cheap, idempotent), but this buffer's own sync/diagnostic/
--- cleanup autocmds are only ever registered on the *first* call.
function M.setup_buffer(bufnr, opts)
  if not opts then
    M.teardown_buffer(bufnr)
    return
  end
  local first_time = state[bufnr] == nil
  if first_time then
    state[bufnr] = {
      shadow = {},
      shadow_paths = {},
      diag_ns = vim.api.nvim_create_namespace('mep_org_polyglot_diag_' .. bufnr),
      scaffold_root = scaffold_root(bufnr),
    }
  end

  M.sync(bufnr)

  if first_time then
    local group = ensure_augroup()
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
      group = group,
      buffer = bufnr,
      callback = function()
        M.sync(bufnr)
      end,
    })
    -- Deferred via vim.schedule: deleting *other* buffers (the shadow
    -- ones) synchronously from inside a BufDelete/BufWipeout handler for
    -- `bufnr` itself crashes Neovim (confirmed empirically while building
    -- this) — those events fire mid-teardown of the triggering buffer,
    -- and `nvim_buf_delete`ing unrelated buffers from within that window
    -- corrupts state. Scheduling runs the actual cleanup on the next
    -- event loop tick instead, once `bufnr`'s own deletion has fully
    -- finished.
    vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
      group = group,
      buffer = bufnr,
      once = true,
      callback = function()
        vim.schedule(function()
          M.teardown_buffer(bufnr)
        end)
      end,
    })
    -- Keeps `status_widget()` live: Neovim only redraws the tabline on
    -- its own on a handful of built-in triggers (window/buffer/mode
    -- changes, ...), none of which fire from moving the cursor between
    -- src blocks (or in and out of one) in the *same* window — the exact
    -- motion `status_widget()` needs to reflect. Only actually redraws
    -- when the reported language changes, not on every single cursor
    -- move, so panning around inside one block (the common case) doesn't
    -- redraw the tabline on every keystroke.
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      buffer = bufnr,
      callback = function()
        local ctx = M.context_at_cursor(bufnr, vim.api.nvim_win_get_cursor(0)[1])
        local ft = ctx and ctx.ft or nil
        local st = state[bufnr]
        if st and st.last_status_ft ~= ft then
          st.last_status_ft = ft
          pcall(vim.cmd.redrawtabline)
        end
      end,
    })
  end

  M.define_default_hl()
  vim.bo[bufnr].omnifunc = "v:lua.require'mep.org.polyglot'.omnifunc"
  bind_keymaps(bufnr, opts.keymaps or {})
end

--- `MepOrgPolyglotStatus` (linked to `ModeMsg` — the same highlight
--- mep.chrome's own analogous "what mode am I in" tabline widget uses,
--- see mep.chrome.statusline's `mode_widget`), `default = true` so a
--- colorscheme defining its own wins. Called once per `setup_buffer`
--- (cheap, idempotent — same "define on every activation" approach
--- mep.org.blockhl's own `define_default_hl` uses) rather than requiring
--- a separate setup step.
function M.define_default_hl()
  vim.api.nvim_set_hl(0, 'MepOrgPolyglotStatus', { link = 'ModeMsg', default = true })
end

--- A `mep.chrome`-shaped widget (`{ text = function(ctx) ... end, hl =
--- ... }` — see mep.chrome.render's own widget contract) showing the
--- language of the src block at the cursor (` python `, ` rust `, ...),
--- or nothing outside an org buffer / outside any src block. Not wired
--- into any tabline/statusline automatically — mep.chrome has no
--- awareness of mep.org (or any other library) and mep.org has none of
--- mep.chrome, the same independence every pair of mep libraries keeps
--- (see README) — compose it into your own config instead:
---
--- require('mep.chrome').setup({ tabline = { widgets_after = {
---   require('mep.org.polyglot').status_widget(),
--- } } })
---
--- `ctx` (mep.chrome's own render-time context, `{ win, bufnr, active }`)
--- is used when given; falls back to the current window/buffer so this
--- also works called plainly (`status_widget().text()`) from anywhere
--- else you might want the same text, e.g. a custom statusline.
function M.status_widget()
  return {
    text = function(ctx)
      local bufnr = (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
      local win = (ctx and ctx.win) or vim.api.nvim_get_current_win()
      if vim.bo[bufnr].filetype ~= 'org' then
        return ''
      end
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if not ok then
        return ''
      end
      local ctx_at_cursor = M.context_at_cursor(bufnr, cursor[1])
      return ctx_at_cursor and (' ' .. ctx_at_cursor.ft .. ' ') or ''
    end,
    hl = 'MepOrgPolyglotStatus',
  }
end

return M

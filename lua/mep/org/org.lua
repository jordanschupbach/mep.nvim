--- Aggregator for mep's org-mode library. "Core" (headline structure +
--- highlighting) plus "Phase 1" (structure editing: subtree-wide
--- promote/demote, move subtree, insert headline, statistics cookies,
--- sort, narrow/widen, archive, refile, global visibility cycling, easy
--- templates) plus "Phase 2" (priority cookies) plus "Phase 3" (dates,
--- scheduling, repeaters) plus "Phase 4" (tag inheritance, match syntax,
--- fast tag-selection, column alignment) plus "Phase 5" (links: parse,
--- conceal, follow, insert, store) plus "Phase 6" (plain lists,
--- sparse-tree search) plus "Phase 7" (property drawers, clocking,
--- effort estimates) plus "Phase 8" (capture templates + command) plus
--- "Phase 9" (agenda: day/week views, global TODO list, tag search) plus
--- "Phase 10" (org-babel: execute/tangle src blocks) plus "Phase 11"
--- (org-export: ascii/markdown/html backends) plus "Phase 12" (special
--- blocks, footnotes, macros, #+INCLUDE:, org-id, attachments) — see
--- ORGMODE_ROADMAP.md for what's still ahead.
--- Highlighting alone is delegated to mep.treesitter (which owns the
--- `org` parser entry in its curated registry); everything else here is
--- pure line-pattern manipulation, no tree-sitter parser needed.
local config = require('mep.org.config')
local headline = require('mep.org.headline')
local outline = require('mep.org.outline')
local todo = require('mep.org.todo')
local priority = require('mep.org.priority')
local checkbox = require('mep.org.checkbox')
local fold = require('mep.org.fold')
local edit = require('mep.org.edit')
local statistics = require('mep.org.statistics')
local sort_mod = require('mep.org.sort')
local narrow_mod = require('mep.org.narrow')
local archive_mod = require('mep.org.archive')
local refile_mod = require('mep.org.refile')
local visibility = require('mep.org.visibility')
local templates = require('mep.org.templates')
local timestamp = require('mep.org.timestamp')
local plan = require('mep.org.plan')
local tags_mod = require('mep.org.tags')
local tagmatch = require('mep.org.tagmatch')
local link_mod = require('mep.org.link')
local linkconceal = require('mep.org.linkconceal')
local list_mod = require('mep.org.list')
local sparse_mod = require('mep.org.sparse')
local property = require('mep.org.property')
local clock = require('mep.org.clock')
local capture = require('mep.org.capture')
local agenda = require('mep.org.agenda')
local babel = require('mep.org.babel')
local block_mod = require('mep.org.block')
local blockhl = require('mep.org.blockhl')
local resultshl = require('mep.org.resultshl')
local headlinehl = require('mep.org.headlinehl')
local todohl = require('mep.org.todohl')
local footnote_mod = require('mep.org.footnote')
local macro_mod = require('mep.org.macro')
local include_mod = require('mep.org.include')
local id_mod = require('mep.org.id')
local attach_mod = require('mep.org.attach')
local export_mod = require('mep.org.export')
local polyglot = require('mep.org.polyglot')

local M = {}
M.headline = headline
M.outline = outline
M.todo = todo
M.priority = priority
M.checkbox = checkbox
M.fold = fold
M.edit = edit
M.statistics = statistics
M.sort = sort_mod
M.narrow = narrow_mod
M.archive = archive_mod
M.refile = refile_mod
M.visibility = visibility
M.templates = templates
M.timestamp = timestamp
M.plan = plan
M.tags = tags_mod
M.tagmatch = tagmatch
M.link = link_mod
M.linkconceal = linkconceal
M.list = list_mod
M.sparse = sparse_mod
M.property = property
M.clock = clock
M.capture = capture
M.agenda = agenda
M.babel = babel
M.block = block_mod
M.blockhl = blockhl
M.resultshl = resultshl
M.headlinehl = headlinehl
M.todohl = todohl
M.footnote = footnote_mod
M.macro = macro_mod
M.include = include_mod
M.id = id_mod
M.attach = attach_mod
M.export = export_mod
M.polyglot = polyglot

local augroup = nil

local function bind_keymaps(bufnr, options)
  local map_opts = { buffer = bufnr, silent = true, nowait = true }
  local function map_all(mode, lhs_list, fn, desc)
    local opts = desc and vim.tbl_extend('force', map_opts, { desc = desc }) or map_opts
    for _, lhs in ipairs(lhs_list) do
      vim.keymap.set(mode, lhs, fn, opts)
    end
  end
  local keymaps = options.keymaps

  local function cursor_line()
    return vim.api.nvim_win_get_cursor(0)[1]
  end

  map_all('n', keymaps.next_headline, function()
    local target = outline.next_headline(bufnr, cursor_line())
    if target then
      vim.api.nvim_win_set_cursor(0, { target, 0 })
    end
  end, 'Next headline')
  map_all('n', keymaps.prev_headline, function()
    local target = outline.prev_headline(bufnr, cursor_line())
    if target then
      vim.api.nvim_win_set_cursor(0, { target, 0 })
    end
  end, 'Previous headline')

  map_all('n', keymaps.promote, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      outline.change_level(bufnr, lnum, -1)
    end
  end, 'Promote the current headline')
  map_all('n', keymaps.demote, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      outline.change_level(bufnr, lnum, 1)
    end
  end, 'Demote the current headline')
  map_all('n', keymaps.promote_subtree, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      outline.change_level_subtree(bufnr, lnum, -1)
    end
  end, 'Promote the whole subtree')
  map_all('n', keymaps.demote_subtree, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      outline.change_level_subtree(bufnr, lnum, 1)
    end
  end, 'Demote the whole subtree')

  map_all('n', keymaps.move_subtree_up, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    local new_start = lnum and outline.move_subtree(bufnr, lnum, -1)
    if new_start then
      vim.api.nvim_win_set_cursor(0, { new_start, 0 })
    end
  end, 'Move the subtree up among its siblings')
  map_all('n', keymaps.move_subtree_down, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    local new_start = lnum and outline.move_subtree(bufnr, lnum, 1)
    if new_start then
      vim.api.nvim_win_set_cursor(0, { new_start, 0 })
    end
  end, 'Move the subtree down among its siblings')

  local function do_insert_headline(fn)
    local new_lnum = fn(bufnr, cursor_line())
    if new_lnum then
      local line = vim.api.nvim_buf_get_lines(bufnr, new_lnum - 1, new_lnum, false)[1]
      vim.api.nvim_win_set_cursor(0, { new_lnum, #line })
      vim.cmd.startinsert()
    end
  end
  map_all('n', keymaps.insert_headline, function()
    do_insert_headline(function(b, l)
      return edit.insert_headline(b, l)
    end)
  end, 'Insert a new sibling headline')
  map_all('n', keymaps.insert_todo_headline, function()
    do_insert_headline(function(b, l)
      return edit.insert_todo_headline(b, l, options.todo_keywords)
    end)
  end, 'Insert a new sibling TODO headline')

  map_all('n', keymaps.cycle_todo, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      todo.cycle(bufnr, lnum, options.todo_keywords)
      statistics.update_ancestors(bufnr, lnum, options.todo_keywords)
    end
  end, 'Cycle TODO state')
  map_all('n', keymaps.cycle_priority, function()
    local lnum = outline.current_headline(bufnr, cursor_line())
    if lnum then
      priority.cycle(bufnr, lnum, options.priorities, options.todo_keywords)
    end
  end, 'Cycle priority cookie')
  map_all('n', keymaps.toggle_checkbox, function()
    local lnum = cursor_line()
    if checkbox.toggle(bufnr, lnum) ~= nil then
      statistics.update_ancestors(bufnr, lnum, options.todo_keywords)
    end
  end, 'Toggle the checkbox under the cursor')

  map_all('n', keymaps.toggle_fold, function()
    vim.cmd('normal! za')
  end, 'Toggle fold under the cursor')
  map_all('n', keymaps.cycle_visibility, function()
    visibility.cycle(bufnr, vim.api.nvim_get_current_win())
  end, 'Cycle global visibility')

  map_all('n', keymaps.sort, function()
    sort_mod.sort_siblings(bufnr, cursor_line(), options.sort_criteria, options.todo_keywords)
  end, "Sort the current headline's siblings")

  map_all('n', keymaps.narrow, function()
    narrow_mod.narrow(bufnr, vim.api.nvim_get_current_win(), cursor_line())
  end, 'Narrow to the current subtree')
  map_all('n', keymaps.widen, function()
    -- try both: a window is never narrowed *and* sparse-tree-restricted
    -- at once in practice, so this is a safe "restore whichever
    -- fold-view feature was last active" no-op-if-inapplicable pair
    local win_ = vim.api.nvim_get_current_win()
    narrow_mod.widen(win_)
    sparse_mod.clear(win_)
  end, 'Widen (undo narrow/sparse-tree)')

  map_all('n', keymaps.archive, function()
    local path = archive_mod.archive_subtree(bufnr, cursor_line())
    if path then
      vim.notify('mep.org: archived to ' .. path, vim.log.levels.INFO)
    end
  end, 'Archive the current subtree')
  map_all('n', keymaps.refile, function()
    refile_mod.refile_interactive(bufnr, cursor_line(), options.todo_keywords)
  end, 'Refile the current subtree')

  map_all('i', keymaps.easy_template, function()
    if not templates.expand_at_cursor(bufnr, vim.api.nvim_get_current_win()) then
      -- fall through to whatever Tab would normally do — feed it back
      -- non-recursively ('n' = noremap) so this mapping doesn't refire
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Tab>', true, false, true), 'n', false)
    end
  end, 'Expand an easy template')

  map_all('n', keymaps.insert_timestamp, function()
    timestamp.insert_or_edit(bufnr, vim.api.nvim_get_current_win(), true)
  end, 'Insert/edit an active timestamp')
  map_all('n', keymaps.insert_inactive_timestamp, function()
    timestamp.insert_or_edit(bufnr, vim.api.nvim_get_current_win(), false)
  end, 'Insert/edit an inactive timestamp')
  map_all('n', keymaps.schedule, function()
    plan.schedule_interactive(bufnr, vim.api.nvim_get_current_win(), cursor_line())
  end, 'Schedule the current headline')
  map_all('n', keymaps.set_deadline, function()
    plan.deadline_interactive(bufnr, vim.api.nvim_get_current_win(), cursor_line())
  end, 'Set deadline on the current headline')

  local function adjust_or_fallback(delta, fallback_key)
    local count = vim.v.count
    if timestamp.adjust_under_cursor(bufnr, vim.api.nvim_get_current_win(), delta * vim.v.count1) then
      return
    end
    -- not on a timestamp: replay the real key (with its count, if any)
    -- non-recursively so Neovim's native increment/decrement still works
    local keys = (count > 0 and tostring(count) or '') .. fallback_key
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', false)
  end
  map_all('n', keymaps.timestamp_increase, function()
    adjust_or_fallback(1, '<C-a>')
  end, 'Increase the timestamp under the cursor')
  map_all('n', keymaps.timestamp_decrease, function()
    adjust_or_fallback(-1, '<C-x>')
  end, 'Decrease the timestamp under the cursor')

  map_all('n', keymaps.select_tags, function()
    tags_mod.select_interactive(bufnr, cursor_line(), options.tags, options.todo_keywords, options.tags_column)
  end, 'Fast tag-selection popup')

  map_all('n', keymaps.follow_link, function()
    link_mod.follow(bufnr, vim.api.nvim_get_current_win(), options.todo_keywords)
  end, 'Follow the link under the cursor')
  local function insert_link()
    link_mod.insert_interactive(bufnr, vim.api.nvim_get_current_win())
  end
  map_all('n', keymaps.insert_link, insert_link, 'Insert a link')
  map_all('v', keymaps.insert_link, insert_link, 'Insert a link (wrap selection as description)')
  map_all('n', keymaps.store_link, function()
    local stored = link_mod.store_link(bufnr, cursor_line(), options.todo_keywords)
    if stored then
      vim.notify('mep.org: stored link to ' .. stored.target, vim.log.levels.INFO)
    end
  end, 'Store a link to the current headline')

  map_all('i', keymaps.list_continue, function()
    local win_ = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win_)
    if not list_mod.continue_at_cursor(bufnr, win_, cursor[1], cursor[2]) then
      -- fall through to a plain newline — feed it back non-recursively
      -- ('n' = noremap) so this mapping doesn't refire
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
    end
  end, 'Continue the list item at the cursor')
  map_all('n', keymaps.list_indent, function()
    list_mod.indent_item(bufnr, cursor_line())
  end, 'Indent the list item at the cursor')
  map_all('n', keymaps.list_outdent, function()
    list_mod.outdent_item(bufnr, cursor_line())
  end, 'Outdent the list item at the cursor')
  map_all('n', keymaps.list_renumber, function()
    list_mod.renumber(bufnr, cursor_line())
  end, 'Renumber the ordered list at the cursor')

  map_all('n', keymaps.sparse_tree, function()
    sparse_mod.search_interactive(bufnr, vim.api.nvim_get_current_win(), options.todo_keywords)
  end, 'Sparse-tree search')

  map_all('n', keymaps.set_property, function()
    property.set_interactive(bufnr, cursor_line())
  end, 'Set a property on the current headline')
  map_all('n', keymaps.clock_in, function()
    local clock_line = clock.clock_in(bufnr, cursor_line())
    if clock_line then
      vim.notify('mep.org: clocked in', vim.log.levels.INFO)
    end
  end, 'Clock in')
  map_all('n', keymaps.clock_out, function()
    local duration = clock.clock_out(bufnr)
    if duration then
      vim.notify('mep.org: clocked out (' .. duration .. ')', vim.log.levels.INFO)
    end
  end, 'Clock out')
  map_all('n', keymaps.clock_report, function()
    clock.insert_report(bufnr, cursor_line())
  end, 'Insert/refresh a clock-table report')

  local function capture_interactive()
    capture.capture_interactive(options.capture_templates)
  end
  map_all('n', keymaps.capture, capture_interactive, 'Capture')
  map_all('v', keymaps.capture, capture_interactive, 'Capture (selection becomes %i)')

  map_all('n', keymaps.agenda, function()
    agenda.dispatch_interactive(options)
  end, 'Open the agenda')

  map_all('n', keymaps.babel_execute, function()
    babel.execute(bufnr, cursor_line())
  end, 'Execute the src block at the cursor')
  map_all('n', keymaps.babel_tangle, function()
    babel.tangle_buffer(bufnr)
  end, 'Tangle every :tangle-targeted block')

  map_all('n', keymaps.ctrl_c_ctrl_c, function()
    local lnum = cursor_line()
    if babel.at_cursor(bufnr, lnum) then
      babel.execute(bufnr, lnum)
      return
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
    if line and checkbox.is_checkbox(line) and checkbox.toggle(bufnr, lnum) ~= nil then
      statistics.update_ancestors(bufnr, lnum, options.todo_keywords)
    end
  end, 'Execute the src block at point, or toggle the checkbox at point')

  map_all('n', keymaps.footnote_action, function()
    local win_ = vim.api.nvim_get_current_win()
    if footnote_mod.at_cursor(bufnr, win_) then
      footnote_mod.goto_counterpart(bufnr, win_)
    else
      footnote_mod.insert_interactive(bufnr, win_)
    end
  end, 'Footnote action (jump, or insert new)')
  map_all('n', keymaps.id_get_create, function()
    id_mod.get_or_create_interactive(bufnr, cursor_line())
  end, 'Get-or-create an :ID: property')
  map_all('n', keymaps.attach, function()
    attach_mod.attach_interactive(bufnr, cursor_line(), options.attach_dir)
  end, 'Attach a file to the current headline')
  map_all('n', keymaps.export_dispatch, function()
    export_mod.dispatch_interactive(bufnr, { todo_keywords = options.todo_keywords })
  end, 'Export (ascii/markdown/html)')
end

local function apply_tags_align_on_save(bufnr, options)
  if not options.tags_column then
    return
  end
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      tags_mod.align_buffer(bufnr, options.tags_column, options.todo_keywords)
    end,
  })
end

local function apply_conceal(bufnr, options)
  if not options.conceal_links then
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

local function apply_block_highlight(bufnr, options)
  if not options.src_block_highlight then
    return
  end
  blockhl.define_default_hl()
  blockhl.apply(bufnr)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      blockhl.apply(bufnr)
    end,
  })
end

local function apply_results_highlight(bufnr, options)
  if not options.results_block_highlight then
    return
  end
  resultshl.define_default_hl()
  resultshl.apply(bufnr)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      resultshl.apply(bufnr)
    end,
  })
end

local function apply_headline_highlight(bufnr, options)
  if not options.headline_highlight then
    return
  end
  headlinehl.define_default_hl()
  headlinehl.apply(bufnr)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      headlinehl.apply(bufnr)
    end,
  })
end

local function apply_todo_highlight(bufnr, options)
  if not options.todo_highlight then
    return
  end
  todohl.define_default_hl()
  todohl.apply(bufnr, options.todo_keywords, options.todo_keyword_colors)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      todohl.apply(bufnr, options.todo_keywords, options.todo_keyword_colors)
    end,
  })
end

local function apply_fold(bufnr, options)
  -- Explicitly reset to Vim's own default ('manual') when disabled,
  -- rather than just skipping — 'foldmethod' is window-local, so a
  -- window that previously showed a fold=true buffer would otherwise
  -- keep stale 'expr' foldmethod/foldexpr for a later buffer whose own
  -- config says fold=false (e.g. two org buffers with different fold
  -- settings shown in the same window one after another).
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if options.fold then
      vim.wo[win].foldmethod = 'expr'
      vim.wo[win].foldexpr = "v:lua.require'mep.org.fold'.foldexpr()"
    else
      vim.wo[win].foldmethod = 'manual'
    end
  end
end

local function apply_highlight(bufnr, options)
  if not options.highlight then
    return
  end
  -- Shares mep.treesitter's `org` registry entry and install pipeline —
  -- if it's already available this resolves ~immediately; otherwise it
  -- clones+compiles in the background and activates once done. Opening
  -- several org buffers before that finishes can kick off a redundant
  -- concurrent install (each temp clone dir is unique, so this is
  -- wasteful rather than broken) — a fine tradeoff for "core" scope.
  require('mep.treesitter.install').install('org', function(ok)
    if ok and vim.api.nvim_buf_is_valid(bufnr) then
      require('mep.treesitter.activate').enable_for_buffer(bufnr, { highlight = true })
    end
  end)
  -- Also install a parser for each language bufnr's src blocks actually
  -- use (mep.org.polyglot.ensure_language_parsers) — org's own parser
  -- being installed doesn't get queries/org/injections.scm anything to
  -- inject on its own.
  --
  -- Once a given language's parser (and, per mep.treesitter.install, its
  -- own queries/ alongside it) lands, two *independent* stale-cache
  -- problems need clearing before it actually shows up highlighted —
  -- confirmed empirically, both against Neovim's own source:
  --
  -- 1. A LanguageTree only ever attempts to resolve a given byte range's
  --    injection language *once* (`_processed_injection_region`, keyed
  --    purely on "has this range been looked at", with no notion of "a
  --    parser that failed to resolve then might succeed now") — real
  --    usage parses+highlights a buffer within its first couple of
  --    redraws, almost always before a background clone+compile can
  --    finish, so the block would otherwise never even get a child tree
  --    for its language. `parser:invalidate(true)` clears the
  --    tree-validity state that gates re-resolution.
  -- 2. Independently, `vim.treesitter.highlighter`'s own per-buffer
  --    instance caches each language's parsed *query* forever once
  --    first asked for (`self._queries[lang]`, `get_query()` in
  --    runtime/lua/vim/treesitter/highlighter.lua — never invalidated
  --    for that instance's lifetime), so even after (1) creates the
  --    child tree, the *same* highlighter instance that already cached
  --    "no query for this language" earlier keeps drawing nothing for
  --    it. Only a genuinely new highlighter instance re-reads queries
  --    from scratch — `enable_for_buffer` (`vim.treesitter.start` again)
  --    does exactly that, discarding the stale one.
  --
  -- Scheduling a redraw after both makes the result visible immediately
  -- rather than on the next incidental edit/cursor-move.
  polyglot.ensure_language_parsers(bufnr, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'org')
    if ok_parser and parser then
      parser:invalidate(true)
    end
    require('mep.treesitter.activate').enable_for_buffer(bufnr, { highlight = true })
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.cmd.redraw)
      end
    end)
  end)
end

local function apply_polyglot(bufnr, options)
  polyglot.setup_buffer(bufnr, options.polyglot)
end

local function activate_org_buffer(bufnr, options)
  apply_highlight(bufnr, options)
  apply_fold(bufnr, options)
  apply_tags_align_on_save(bufnr, options)
  apply_conceal(bufnr, options)
  apply_block_highlight(bufnr, options)
  apply_results_highlight(bufnr, options)
  apply_headline_highlight(bufnr, options)
  apply_todo_highlight(bufnr, options)
  -- Editing keymaps and poly-mode LSP (real shadow buffers, real
  -- language-server attach, real scaffold files on disk — see
  -- mep.org.polyglot's own header comment) only make sense for a buffer
  -- the user can actually edit. A non-modifiable buffer with filetype
  -- 'org' is never that: it's some other library's read-only preview
  -- (confirmed the hard way against mep.picker's own preview pane —
  -- `preview.lua` copies a source buffer's lines into a scratch,
  -- `modifiable=false` buffer and sets its filetype to match, purely for
  -- syntax coloring; every re-render re-fires this same FileType
  -- autocmd, so without this guard each keystroke while previewing an
  -- org file spun up a *fresh* poly-mode LSP session — real shadow
  -- buffers and, for any src-block language with a curated `mep.lsp`
  -- server on PATH, a real attached client — for a buffer that gets
  -- wiped the moment the picker closes or the selection changes. Torn
  -- down shadow buffers can still have an in-flight diagnostics
  -- notification arrive after that, which is what actually surfaced as
  -- "Invalid buffer id" errors right after picking a result). Every
  -- *coloring*-only activation above stays on regardless — highlighting
  -- a read-only preview accurately is exactly the point.
  if vim.bo[bufnr].modifiable then
    bind_keymaps(bufnr, options)
    apply_polyglot(bufnr, options)
  end
end

--- Configure mep.org. See mep.org.config.defaults for
--- todo_keywords/todo_highlight/todo_keyword_colors/highlight/fold/
--- sort_criteria/priorities/tags/tags_column/conceal_links/keymaps.
function M.setup(opts)
  local options = config.setup(opts)

  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = vim.api.nvim_create_augroup('MepOrg', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = 'org',
    callback = function(args)
      activate_org_buffer(args.buf, options)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'org' then
      activate_org_buffer(bufnr, options)
    end
  end

  return options
end

return M

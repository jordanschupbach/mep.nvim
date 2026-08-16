local M = {}

M.defaults = {
  -- Keywords recognized (in order) as a headline's TODO state. cycle_todo
  -- steps through this list and then to "no keyword".
  todo_keywords = { 'TODO', 'DONE' },
  -- Give each todo_keywords entry its own color in the buffer — real
  -- org-mode's own look (TODO red, DONE green) generalized to whatever
  -- keywords you configure. See mep.org.todohl. Set to false to leave
  -- keywords uncolored (queries/org/highlights.scm's own static
  -- TODO=@keyword/DONE=@comment captures still apply — just none of your
  -- own custom states).
  todo_highlight = true,
  -- Highlight group each keyword (a key here, case-sensitive, matching
  -- one in todo_keywords above) links to — any real highlight group: a
  -- built-in one like below, a colorscheme's own, or one you define
  -- yourself. A todo_keywords entry with no color here (e.g. a custom
  -- state you added but didn't also color) cycles through
  -- mep.org.todohl.LINKS instead, positionally within todo_keywords —
  -- same fallback mep.org.headlinehl uses for headline levels past its
  -- own fixed rotation.
  todo_keyword_colors = {
    TODO = 'DiagnosticError',
    DONE = 'DiagnosticOk',
  },
  -- Highlight org buffers via mep.treesitter (installing the `org`
  -- parser in the background if it isn't available yet — see
  -- mep.treesitter.config for what that needs).
  highlight = true,
  -- Set a headline-depth-based 'foldexpr' (org's actual fold unit is the
  -- headline subtree; see mep.org.fold for why that's not the same as
  -- generic treesitter folding). cycle_visibility and narrow/widen also
  -- depend on this.
  fold = true,
  -- Default criteria for the `sort` keymap — a key into
  -- mep.org.sort.criteria ('alpha', 'todo', or 'priority'), or a custom
  -- function(parsed, todo_keywords).
  sort_criteria = 'alpha',
  -- Priority letters recognized by the `cycle_priority` keymap, in
  -- highest-to-lowest order.
  priorities = { 'A', 'B', 'C' },
  -- Known tags offered by the `select_tags` fast tag-selection popup
  -- (real org-mode's `org-tag-alist`) — empty by default, since there's
  -- no sensible default tag vocabulary.
  tags = {},
  -- 1-based column trailing `:tag:` blocks are aligned to, both
  -- immediately after `select_tags` confirms and automatically before
  -- saving an org buffer (mep.org.tags.align_line/align_buffer). Set to
  -- false to disable auto-alignment entirely.
  tags_column = 77,
  -- Visually hide the raw "[[target][" / "]]" syntax of a link, showing
  -- only its description (or bare target with no description) — see
  -- mep.org.linkconceal. Sets 'conceallevel'/'concealcursor' on windows
  -- showing an org buffer.
  conceal_links = true,
  -- Capture templates: a list of `{ key, description, target = { file =
  -- ..., headline = ... }, template = "..." }` — see mep.org.capture for
  -- the template placeholder syntax (%?, %a, %i, %T/%U, %t/%u, %^{...}).
  -- Empty by default, since there's no sensible default target file.
  capture_templates = {},
  -- Files/directories (literal paths and/or glob patterns, e.g.
  -- "~/notes/*.org") feeding mep.org.agenda. Empty by default, since
  -- there's no sensible default set of files.
  agenda_files = {},
  -- How many days ahead an upcoming DEADLINE starts appearing in the day
  -- agenda view (real org-mode's `org-deadline-warning-days` default).
  deadline_warning_days = 14,
  -- Root directory (relative to a buffer's own file, or absolute) that
  -- mep.org.attach copies attachments under, split into a headline's own
  -- `:ID:`-derived subdirectory — real org-attach's own default
  -- `org-attach-directory`.
  attach_dir = 'data',
  -- Give `#+begin_src ... #+end_src` blocks a distinct background (linked
  -- to `CursorLine` by default — see mep.org.blockhl) so they stand out
  -- from surrounding prose. Set to false to leave them with no background
  -- beyond whatever `queries/org/highlights.scm`'s generic block span
  -- already gives them.
  src_block_highlight = true,
  -- Give `#+RESULTS:` blocks (a one-line `: value`, a `#+begin_example
  -- ... #+end_example` block, or just the `#+RESULTS:` line itself for
  -- an empty result) a distinct color, so a src block's computed output
  -- reads as a literal value rather than plain prose (linked to
  -- `Constant` by default — see mep.org.resultshl). Set to false to
  -- leave them with no color of their own.
  results_block_highlight = true,
  -- Give each headline level its own distinct color (level 1 blue,
  -- cycling through a fixed 6-color rotation after that — see
  -- mep.org.headlinehl's own `LINKS` table) instead of every level
  -- sharing `queries/org/highlights.scm`'s single `@markup.heading`
  -- capture. Set to false to leave every level that one shared color.
  headline_highlight = true,
  -- "Poly mode": while the cursor is inside a `#+begin_src <lang> ...
  -- #+end_src` block, real LSP features (hover, definition, references,
  -- rename, diagnostics, manual completion) come from *that language's*
  -- own attached server instead of doing nothing — see mep.org.polyglot.
  -- Set to `false` to disable entirely; a table overrides just
  -- `keymaps`. Syntax highlighting for each embedded language (also part
  -- of "poly mode") isn't gated by this option at all — it's tree-sitter
  -- language injection (queries/org/injections.scm), active automatically
  -- any time org highlighting itself (`highlight` above) is, as long as
  -- that language's own parser happens to be installed.
  polyglot = {
    keymaps = {
      goto_definition = { 'gd' },
      goto_declaration = { 'gD' },
      references = { 'gr' },
      implementation = { 'gi' },
      type_definition = { '<leader>lt' },
      hover = { 'K' },
      signature_help = { '<C-k>' },
      rename = { '<leader>rn' },
      diagnostic_prev = { '[d' },
      diagnostic_next = { ']d' },
      diagnostic_prev_error = { '[e' },
      diagnostic_next_error = { ']e' },
      diagnostic_float = { '<leader>le' },
    },
  },
  keymaps = {
    next_headline = { '<C-c><C-n>' },
    prev_headline = { '<C-c><C-p>' },
    promote = { '<Mod1-Left>' },
    demote = { '<Mod1-Right>' },
    promote_subtree = { '<Mod1-S-Left>' },
    demote_subtree = { '<Mod1-S-Right>' },
    move_subtree_up = { '<Mod1-S-Up>' },
    move_subtree_down = { '<Mod1-S-Down>' },
    insert_headline = { '<Mod1-CR>' },
    insert_todo_headline = { '<Mod1-S-CR>' },
    cycle_todo = { '<C-c><C-t>' },
    cycle_priority = { '<C-c>,' },
    -- Standalone checkbox-toggle binding — unbound by default since real
    -- org-mode (and this project) puts checkbox toggling on `<C-c><C-c>`
    -- via ctrl_c_ctrl_c below instead; set this if you want toggling
    -- reachable on its own key too.
    toggle_checkbox = {},
    toggle_fold = { '<Tab>' },
    cycle_visibility = { '<S-Tab>' },
    sort = { '<C-c>^' },
    narrow = { '<C-c>n' },
    widen = { '<C-c>N' },
    archive = { '<C-c><C-x><C-a>' },
    refile = { '<C-c><C-w>' },
    -- Insert-mode only: expands "<s<Tab>" etc. into a block, falling
    -- back to normal Tab behavior otherwise — see mep.org.templates.
    easy_template = { '<Tab>' },
    insert_timestamp = { '<C-c>.' },
    insert_inactive_timestamp = { '<C-c>!' },
    schedule = { '<C-c><C-s>' },
    set_deadline = { '<C-c><C-d>' },
    -- Shadow Neovim's native increment/decrement *only* while the cursor
    -- is on a timestamp (adjusting it by [count] days, default 1);
    -- falls back to real <C-a>/<C-x> otherwise — see mep.org.org's
    -- wiring and mep.org.timestamp.adjust_under_cursor.
    timestamp_increase = { '<C-a>' },
    timestamp_decrease = { '<C-x>' },
    -- Fast tag-selection popup (real org-mode's `org-set-tags-command`) —
    -- kept off <C-c><C-c>, which this project already dedicates to
    -- checkbox toggling.
    select_tags = { '<C-c><C-q>' },
    follow_link = { '<C-c><C-o>' },
    -- Bound in both normal and visual mode — see mep.org.link.insert_interactive.
    insert_link = { '<C-c><C-l>' },
    store_link = { '<C-c>l' },
    -- Insert-mode only: continues the list at the cursor (fresh
    -- bullet/next number, or exits the list on an empty item), falling
    -- back to a plain newline otherwise — see mep.org.list.continue_at_cursor.
    list_continue = { '<CR>' },
    list_indent = { '<C-c>>' },
    list_outdent = { '<C-c><' },
    list_renumber = { '<C-c>#' },
    -- Real org-mode's `C-c /` also asks (via a menu) what kind of
    -- sparse-tree search to run — see mep.org.sparse.search_interactive.
    sparse_tree = { '<C-c>/' },
    set_property = { '<C-c><C-x>p' },
    clock_in = { '<C-c><C-x><C-i>' },
    clock_out = { '<C-c><C-x><C-o>' },
    clock_report = { '<C-c><C-x><C-r>' },
    -- Bound in both normal and visual mode, like insert_link — real
    -- org-capture is actually a *global* keymap (any buffer, not just
    -- org ones); see mep.org.capture's module comment for how to get
    -- that yourself.
    capture = { '<C-c>c' },
    -- Real org-agenda is also a *global* keymap; see mep.org.agenda's
    -- module comment for how to get that yourself.
    agenda = { '<C-c>a' },
    -- Not real org-babel's own `C-c C-v C-e`/`C-c C-v C-t` (an Emacs
    -- convention) — confirmed empirically that `<C-v>` can't work as the
    -- first key of a Neovim mapping (it hard-codes to entering
    -- Visual-Block mode before mapping resolution even sees it, for
    -- both synthetic and real input). Mirrors this project's own
    -- `narrow`/`widen` (`<C-c>n`/`<C-c>N`) convention instead:
    -- lowercase acts on the block at point, uppercase acts on the whole
    -- buffer.
    babel_execute = { '<C-c>e' },
    babel_tangle = { '<C-c>E' },
    -- Real org-mode's own `org-ctrl-c-ctrl-c` is heavily overloaded,
    -- dispatching on whatever's at point; this project's version only
    -- knows two contexts, checked in that order — see mep.org.org's
    -- wiring: execute the src block at point (mep.org.babel.execute) if
    -- the cursor is inside one, else toggle the checkbox at point
    -- (mep.org.checkbox.toggle) if it's on one. Does nothing in any other
    -- context, rather than guessing.
    ctrl_c_ctrl_c = { '<C-c><C-c>' },
    -- Real org-footnote-action's own binding: jumps from a reference to
    -- its definition (or back), or inserts a new footnote when the
    -- cursor is on neither.
    footnote_action = { '<C-c><C-x>f' },
    -- Real org-id-get-create has no stock binding; this project gives it
    -- one for discoverability, consistent with set_property's own
    -- <C-c><C-x> prefix.
    id_get_create = { '<C-c><C-x>i' },
    attach = { '<C-c><C-a>' },
    -- Real org-export-dispatch's own binding.
    export_dispatch = { '<C-c><C-e>' },
  },
}

local keys = require('mep.core.keys')

-- Expanded through mep.core.keys so `<Mod1-...>` placeholders (in the
-- defaults and in user-supplied keymaps alike) become the concrete
-- per-platform modifier — see mep.config.defaults.mods.
M.options = keys.expand_table(vim.deepcopy(M.defaults))

function M.setup(opts)
  M.options = keys.expand_table(vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {}))
  return M.options
end

return M

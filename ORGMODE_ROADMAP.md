# mep.org — path to org-mode feature parity

Tracking document for expanding `mep.org` from "core structure +
highlighting" toward as much of Emacs org-mode's functionality as is
reasonable to build here, including org-babel and org-export. Real
org-mode (and even the mature community
[orgmode.nvim](https://github.com/nvim-orgmode/orgmode), years of
development) is an enormous surface — this file exists so "what's left"
is always a quick read rather than a guess, and so work happens in a
sensible dependency order instead of wherever's most fun that day.

**How to use this file**: check an item off when it ships, with real test
coverage (per `CLAUDE.md` — every feature here gets a spec). Add newly
discovered sub-items as they turn up; this list was written from
knowledge of org-mode's feature set, not by exhaustively re-reading the
Emacs manual, so it will be incomplete in places. Phases are ordered by
rough dependency + value, not by difficulty — feel free to reorder if a
later phase turns out to unblock something sooner.

## Phase 0 — Core (done)

Shipped in the previous round. Everything here is pure line-pattern
parsing (`mep.org.headline`) except highlighting, so it works even
without the `org` tree-sitter parser installed.

- [x] Headline parsing: stars → level, leading TODO keyword, title, trailing `:tag:` list (`mep.org.headline`)
- [x] Outline navigation: next/prev headline, parent, subtree bounds (`mep.org.outline`)
- [x] Promote/demote a single headline (not its subtree yet — see Phase 1)
- [x] TODO state cycling through a configured keyword list, back to "no keyword" (`mep.org.todo`)
- [x] Checkbox toggling, `- [ ]` / `- [X]` (`mep.org.checkbox`)
- [x] Headline-depth folding via a custom `foldexpr` — the fold unit is the subtree, not every syntax node (`mep.org.fold`)
- [x] Syntax highlighting via `mep.treesitter`'s `org` parser entry + a hand-written `queries/org/highlights.scm` (headlines, TODO/DONE, tags, checkboxes, blocks, drawers, comments, timestamps)
- [x] Buffer-local keymaps for all of the above, configurable via `setup({ keymaps = {...} })`

## Phase 1 — Structure editing polish (done)

The stuff you touch constantly while actually writing an org file; makes
the difference between "has org syntax highlighting" and "is usable as
an outliner."

- [x] Insert a new headline at point (`M-RET` equivalent) — same level as current. Deliberately simpler than real org-mode: always inserts an *empty* headline after the current subtree rather than splitting text after the cursor onto it — see `mep.org.edit`.
- [x] Insert a new TODO headline directly (`M-S-RET` equivalent)
- [x] Promote/demote a whole **subtree**, not just the one headline (`M-S-Left`/`M-S-Right`) — Phase 0's `promote`/`demote` only touches the current line
- [x] Move subtree up/down among its siblings (`M-S-Up`/`M-S-Down`)
- [x] Statistics cookies: `[n/m]` and `[n%]` in a headline auto-update when a child checkbox or child-headline TODO state changes (`mep.org.statistics`, wired into `cycle_todo`/`toggle_checkbox`)
- [x] Sort sibling entries (by title or TODO state so far — priority/timestamp sort keys wait on Phase 2/3's parsing)
- [x] Narrow buffer to the current subtree / widen back out — a practical fold-based approximation, not true Emacs-style narrowing (see `mep.org.narrow`)
- [x] Archive subtree (`org-archive-subtree`) — moves to a configured (or default `<file>_archive.org`) archive file, not the `::ARCHIVE` sibling-tree variant
- [x] Refile: move the current subtree to another headline, with picker-style completion via `mep.picker` — currently within the same buffer only; cross-file refiling waits on Phase 9/agenda's multi-file support
- [x] Global visibility cycling — a 3-state overview → contents → all cycle (matching modern org-mode's actual behavior), not per-headline fold toggling
- [x] "Easy templates": type e.g. `<s` then Tab to expand into a `#+begin_src ... #+end_src` block (and similarly for quote/example/center/verse/comment)

## Phase 2 — Priorities (done)

- [x] Parse `[#A]` / `[#B]` / `[#C]` priority cookies in `mep.org.headline` — single alphanumeric character (`%w`, not letters-only), immediately after the TODO keyword if any
- [x] Keymap to cycle/set priority on the current headline (`mep.org.priority`, `<C-c>,`) — cycles through a configured list rather than real org-mode's prompt-based `org-priority`, consistent with `mep.org.todo`'s own cycle-based approach
- [x] Priority reflected in highlighting (extend `queries/org/highlights.scm`) — matched by literal `[#X]`-shaped text (`@constant`), same "no dedicated grammar node" tradeoff as the existing TODO/DONE matching
- [x] Priority as a sort key (`mep.org.sort.criteria.priority`) — plain string comparison, no-priority sorts last

## Phase 3 — Dates, scheduling, and repeaters (done)

Foundational for Phase 7 (agenda) — build this before agenda, not after.

- [x] Parse active `<2024-01-01 Mon>` and inactive `[2024-01-01 Mon]` timestamps, with optional time and repeater (`+1w`, `++1w`, `.+1w`) — `mep.org.timestamp`, pure line-pattern parsing (no tree-sitter needed); the weekday is always recomputed rather than trusted from parsed/typed text
- [x] Parse `SCHEDULED:` / `DEADLINE:` planning lines under a headline — `mep.org.plan`
- [x] Insert/edit a timestamp at point (`org-time-stamp` equivalent) — `mep.org.timestamp.insert_or_edit`, `<C-c>.`/`<C-c>!` (active/inactive), interactive via `vim.ui.input`
- [x] Increase/decrease the date under the cursor by a day/week (`<C-a>`/`<C-x>` equivalent — mind the clash with Neovim's own increment/decrement keys, likely needs different defaults) — resolved by shadowing `<C-a>`/`<C-x>` *only* while the cursor is actually on a timestamp, falling back (count preserved) to Neovim's native increment/decrement otherwise, the same fallback pattern Phase 1's easy-template `<Tab>` uses; a week is `7<C-a>` (Vim's native count prefix), no separate keymap needed
- [x] Schedule / set-deadline commands on the current headline — `mep.org.plan.schedule_interactive`/`deadline_interactive`, `<C-c><C-s>`/`<C-c><C-d>` (matching real org-mode's own defaults)

## Phase 4 — Tags (extending Phase 0's basic parsing) (done)

- [x] Tag inheritance: a headline is considered tagged with everything
      its ancestors are tagged with, for search/matching purposes —
      `mep.org.tags.effective_tags`, deduped, own tags first then each
      ancestor's (nearest first)
- [x] Tag match syntax (`+work-urgent`, etc.) as a filter predicate, shared by sparse-tree search (Phase 6) and agenda (Phase 7) — `mep.org.tagmatch`; implicit AND by concatenation, `|` for OR, AND binds tighter than OR (`+a+b|+c` = `(a AND b) OR c`); deliberately no parenthesized grouping or TODO/property terms mixed in, tags-only scope
- [x] Fast tag-selection UI (single-key toggle per configured tag) — `mep.org.tags.select_interactive`, `<C-c><C-q>` (kept off `<C-c><C-c>`, already dedicated to checkbox toggling); a small floating popup with auto-assigned single-letter shortcuts (`assign_shortcuts`), `<CR>` to confirm, `<Esc>`/`q` to cancel
- [x] Auto-align trailing tags to a consistent column on save/edit — `mep.org.tags.align_line`/`align_buffer` (1-based `tags_column`, default 77; single space instead of truncating when the headline already overflows the column, matching real org-mode); wired to a per-buffer `BufWritePre` autocmd and to `select_interactive`'s confirm step

## Phase 5 — Links (done)

- [x] Parse `[[target]]` and `[[target][description]]` — `mep.org.link`, pure line-pattern parsing (no dedicated link/link_desc node exists in the real grammar at all, confirmed against `node-types.json` back in Phase 0 and reconfirmed here)
- [x] Conceal the raw `[[...]]` syntax, showing only the description — `mep.org.linkconceal`, extmark-based (not tree-sitter — same reason as above, no node to hang a `@conceal` capture off of); recomputed on `TextChanged`/`TextChangedI`/`InsertLeave`, so purely programmatic buffer edits (not real typing) need an explicit `apply(bufnr)` call to refresh
- [x] Follow the link under cursor: open a URL, jump to a heading (by exact
      text, `#custom-id`, or `id:`), or open a file link — `mep.org.link.follow`/`open_target`; URLs go through `vim.ui.open` (Neovim 0.10+, degrades gracefully with a notification below that); `id:`/`#custom-id` read a headline's own `:PROPERTIES:` drawer with the smallest scanner that gets this working now (full property-drawer parsing is properly Phase 7's job — same "narrow slice now, Phase 7 generalizes it later" tradeoff `mep.org.archive` already made); a bare target tries a same-buffer heading-title search first, then falls back to a relative file path, deliberately simpler than real org-mode's fuzzy/regex text search
- [x] Insert a link (prompt for target + description, or wrap a visual selection as the description) — `mep.org.link.insert_interactive`, `<C-c><C-l>` (bound in both normal and visual mode)
- [x] Store a link to the current headline for later insertion elsewhere — `mep.org.link.store_link`, `<C-c>l`; prefers `CUSTOM_ID`, then `ID`, then a `*Title` fallback; only the single most recently stored link is kept, not a history list like real org-mode's

## Phase 6 — Lists and sparse-tree search (done)

- [x] Plain list item continuation: pressing Enter in a list continues the list (bullet or ordered-number) — `mep.org.list.continue_at_cursor`, insert-mode `<CR>` (falls back to a plain newline off a list item, same fallback pattern as Phase 1's easy-template `<Tab>`); a checkbox item continues with a fresh unchecked `[ ]`; pressing Enter on an *empty* item exits the list instead of adding another one, matching real org-mode
- [x] Renumber an ordered list — `mep.org.list.renumber`, `<C-c>#`; always restarts from 1 and requires a contiguous run (no blank-line gaps tolerated), simpler than real org-mode on both counts; runs automatically after `continue_at_cursor` adds a new ordered item, so numbers self-heal without a manual keypress in the common case
- [x] Indent/outdent a list item (and its children) as a unit — `mep.org.list.indent_item`/`outdent_item`, `<C-c>>`/`<C-c><` (headline promote/demote already owns `<M-Left>`/`<M-Right>`/`<M-S-Left>`/`<M-S-Right>`, so lists needed their own keys rather than real org-mode's context-sensitive reuse of those); "children" means more-deeply-indented lines directly beneath the item, stopping at the first line that isn't (no blank-line tolerance, matching `mep.org.sort`'s sibling-scoping simplicity) — renumbering after indent/outdent is a manual `<C-c>#` follow-up, not automatic
- [x] Sparse tree: given a tag/property/TODO-state query, fold everything except matching headlines (and their ancestors) — this is what real org-mode's `C-c /` gives you, and it's a natural search UI to expose through `mep.picker` — `mep.org.sparse`, `<C-c>/` (prompts tag vs. TODO state via `vim.ui.select`, matching real org-mode's own "ask a type first" UX); tag search reuses Phase 4's `mep.org.tagmatch`/`mep.org.tags.effective_tags` (its first real consumer); TODO-state search picks the keyword via `mep.picker` (the "expose through mep.picker" the roadmap asked for); property-query search is deferred to Phase 7, once real property-drawer parsing exists to search against; `widen` (`<C-c>N`) now tries both `mep.org.narrow.widen` and `mep.org.sparse.clear`, since a window is never narrowed *and* sparse-tree-restricted at once in practice — one key reverts whichever fold-view feature was last active

## Phase 7 — Drawers, properties, and clocking (done)

- [x] Parse `:PROPERTIES: ... :END:` drawers into a key/value map per headline — `mep.org.property.parse` (an ordered list preserving casing/duplicates, plus a case-insensitive `by_key` lookup); generalizes the narrow ad-hoc `:ID:`/`:CUSTOM_ID:` scanner `mep.org.link` carried since Phase 5 — that module now delegates here instead of duplicating the logic
- [x] Get/set a property programmatically (foundation for effort estimates, custom IDs, agenda filtering by property) — `mep.org.property.get`/`set`/`remove`/`find_by`, `set_interactive` (`<C-c><C-x>p`, real org-mode's `org-set-property`)
- [x] `:LOGBOOK:` drawer: state-change notes, clock entries — `mep.org.clock.find_logbook`; state-change notes (e.g. `- State "DONE" from "TODO"`) are deliberately out of scope, real org-mode's `org-log-done` note-taking is a whole feature on its own not asked for here
- [x] Clock in / clock out on the current headline, recording a `CLOCK:` entry — `mep.org.clock.clock_in`/`clock_out`, `<C-c><C-x><C-i>`/`<C-c><C-x><C-o>` (real org-mode's own bindings); only one clock can be open at a time, found by scanning the buffer for an open `CLOCK:` line rather than tracked as session-only state, so it survives buffer reloads and Neovim restarts (slower for a huge file, but more correct)
- [x] Show the currently clocked-in task + elapsed time somewhere visible (statusline component) — `mep.org.clock.status(bufnr)` returns a `"Title (H:MM)"` string; this project has zero runtime deps and no opinion on statusline plugins, so it's a plain function for users to wire into their own `'statusline'`, not an integration
- [x] Clock table report (`#+BEGIN: clocktable ... #+END:`) — `mep.org.clock.report`/`render_table`/`insert_report`, `<C-c><C-x><C-r>`; recursive per-headline totals (a parent's total includes its descendants'), refreshes an existing block in place or inserts a new one
- [x] Effort estimates (an `Effort:` property) — `mep.org.clock.effort(bufnr, lnum)` reads it via `mep.org.property` and parses `"H:MM"`/bare-minutes via the same `parse_duration` clock-table rendering uses. Summing/displaying effort totals *in the agenda* did not end up part of Phase 9's actual scope (see that phase's notes) — `effort()` is available for a future pass to wire in

## Phase 8 — Capture (done)

- [x] Capture templates: configured target file/headline + a template string with placeholders (`%?`, `%T`/timestamp, `%a`/annotation, etc.) — `config.capture_templates`, a list of `{ key, description, target = { file = ..., headline = ... }, template = "..." }`; `mep.org.capture.expand` handles `%?` (cursor position), `%a` (annotation, an org-link back to where capture was triggered), `%i` (initial content — a visual selection, if capture was invoked from visual mode), `%T`/`%U` (active timestamp), `%t`/`%u` (inactive — real org-mode distinguishes "with time" `%U`/`%u` from date-only `%T`/`%t`, this project doesn't, a deliberate simplification), `%^{PROMPT}` (a `vim.ui.input` prompt, resolved in order for multiple prompts), `%%` (literal percent) via a single left-to-right token scan — not sequential `gsub` passes, which would risk misinterpreting `%`-shaped text *inside* a substituted annotation/prompt-answer as another placeholder
- [x] Capture command: pick a template (via `mep.picker`), open a scratch buffer/popup, insert the filled template into the target on confirm — `mep.org.capture.capture_interactive`, `<C-c>c` (normal or visual); the popup is filetype `org` (so the rest of this library's keymaps work inside it too), `<C-c><C-c>` files it and saves, `<C-c><C-k>` aborts (real org-mode's own capture-buffer bindings). Real `org-capture` is bound *globally*, not just in org buffers, since quick capture from anywhere is the whole point — this project's keymaps only activate inside org buffers (see `mep.org.org`'s FileType-triggered architecture), so `capture_interactive` is also a plain function meant to be bound to a global keymap by the user for the real "capture from anywhere" experience — see README.md

## Phase 9 — Agenda (done)

The single biggest remaining "core org-mode" feature, and the one most
dependent on earlier phases (dates/scheduling, tags, properties) actually
existing first.

- [x] `org_agenda_files`-style configuration: which files/directories feed the agenda — `config.agenda_files`, a list of literal paths and/or glob patterns (e.g. `{'~/notes/*.org'}`); `mep.org.agenda.files` resolves/dedupes/sorts them into an actual file list
- [x] Day/week agenda view aggregating scheduled items + deadlines across all agenda files into one buffer — `mep.org.agenda.show_day`/`show_week`, built on `collect_entries` (every headline across the resolved files, reusing `mep.org.headline`/`mep.org.plan`/`mep.org.timestamp`/`mep.org.tags.effective_tags`) + `entries_for_date`/`occurs_on` for repeater-aware occurrence matching; reads live/unsaved buffer content for any agenda file already open (`vim.fn.bufadd`+`bufload`, the same idiom Phase 8's capture uses for its target file), not just what's on disk
- [x] Global TODO list view (every TODO-stated headline across agenda files) — `mep.org.agenda.show_todo_list`/`todo_view`; excludes the last configured `todo_keywords` entry ("done"), the same "last keyword = done" convention `mep.org.statistics` already uses elsewhere
- [x] Tag/property search view (built on Phase 4's match syntax) — tags only: `mep.org.agenda.show_tag_search`/`tag_search_view`, reusing `mep.org.tagmatch` (prompted via `vim.ui.input`, `show_tag_search_interactive`). Property search is explicitly **not** implemented this phase — `mep.org.property` (Phase 7) exists but isn't wired into a search view; deferred rather than half-built, since it needs its own query syntax design
- [x] Jump from an agenda line to its source location — `<CR>` in the agenda buffer closes the agenda split and jumps to the entry's source (buffer + line) in the window that opened it
- [x] Change TODO state / reschedule directly from the agenda buffer — `t` cycles TODO state at the source (`mep.org.todo.cycle`) and redraws the agenda in place (`opts.refresh`); `s` reschedules (`mep.org.plan.schedule_interactive`). Both act on the loaded buffer only, not saved to disk automatically — consistent with how `cycle_todo`/scheduling behave everywhere else in this project
- [x] Deadline/scheduled warning windows (show upcoming deadlines N days ahead) — `config.deadline_warning_days` (default `14`, matching real org-mode's `org-deadline-warning-days`); `entries_for_date`'s `warning_days` parameter surfaces upcoming deadlines, `include_overdue` (only passed for the actual current day, not arbitrary browsing) surfaces already-overdue non-repeating deadlines

Agenda is opened via `M.open`: a `botright new` split, filetype
`org-agenda` (deliberately distinct from `org` so the main FileType
autocmd doesn't also fire on it), `q` closes it. `dispatch_interactive`
(`<C-c>a`) prompts for a view (day/week/todo/tags) via `vim.ui.select` —
real org-agenda's own `C-c a` similarly asks first. Like Phase 8's
capture, real org-agenda is a *global* keymap (works from any buffer);
this project only activates keymaps inside org buffers, so
`dispatch_interactive(config)` is also a plain function meant to be bound
to a global keymap by the user — see README.md.

**Notes on scope decisions:**
- All three repeater cadence variants (`+N`, `++N`, `.+N`) are treated identically by `occurs_on` for occurrence-matching. Real org-mode's `.+` actually means "N units after whenever this was last *completed*", which needs completion-history tracking this project doesn't have — a deliberate simplification, not an oversight.
- The day/week view is not gated on TODO state (an item stays visible after being marked DONE, just rendered with its new keyword) — only the global TODO list view filters by state. This matches real org-agenda's own default (`org-agenda-skip-scheduled-if-done` is off by default).
- Effort totals are not shown/summed in the agenda, despite Phase 7's `mep.org.clock.effort` being built with that in mind — the checklist that actually shaped this phase's work didn't include it, so it was left out rather than added unprompted; `effort(bufnr, lnum)` is there for a future pass.

**Real bugs found and fixed via testing** (busted + a real-headless-Neovim smoke test, per `CLAUDE.md`):
- `agenda.files` originally called `vim.fn.expand()` on a glob pattern *before* `vim.fn.glob()`. `expand()` on a pattern containing wildcards already resolves it into a newline-joined string of every match, which `glob()` then can't reparse as a pattern — so any real multi-file glob (e.g. `agenda_files = {'~/notes/*.org'}`) silently resolved to zero files. Fixed by calling `glob()` directly (it natively handles both `~`/env-var and wildcard expansion) and only falling back to `expand()`+`filereadable` for a literal non-matching path.
- `M.open`'s `q` keymap closed the agenda split via a bare `nvim_win_close` with no explicit focus restoration, unlike `<CR>`'s handler (which explicitly restores `prev_win`). This only diverges from Neovim's default "return to previous window" behavior in unusual layouts (confirmed via the smoke test using a floating window as the main editing window) — but real org-agenda's `org-agenda-quit` always restores the pre-agenda window configuration regardless of layout, so `q` now does the same explicit restoration `<CR>` already did.

## Phase 10 — org-babel (code execution) (done)

- [x] Parse `#+begin_src <lang> [header args] ... #+end_src` into language + body + header arguments — `mep.org.babel.find_blocks`/`at_cursor`, pure line-pattern parsing (case-insensitive on `begin_src`/`end_src`, matching every other mep.org module's approach), consistent with `queries/org/highlights.scm` still only treating the whole block as one opaque highlight span (a structural-parsing concern, not a highlighting one). `parse_header_args` reads the `#+begin_src` line's own inline args only — `#+header:` continuation lines above a block aren't read, a deliberate scope-narrowing (covers the common case; long multi-line header-arg lists are real org-mode's escape hatch, not something this project needs to match)
- [x] Execute a code block's body via `core.job` (the same building block `mep.treesitter`'s installer already shells out through) and insert/update a `#+RESULTS:` block below it — `mep.org.babel.execute`, `<C-c>e`; writes the block body to a real temp script file and runs it through the resolved interpreter, capturing stdout into a `#+RESULTS:` block (a colon-prefixed `: line` for single-line output, a `#+begin_example ... #+end_example` block for multi-line — real org-mode's own two conventions), replacing an existing results block in place on re-execution rather than duplicating it. A failed run (nonzero exit) still writes whatever stdout it produced and separately warns via `vim.notify` with the first line of stderr, so failures stay visible instead of an empty results block silently swallowing them
- [x] Support an initial set of common languages (lua, python, sh/bash, javascript/node) — `mep.org.babel.languages` (`lua`, `python`/fallback `python`←`python3`, `sh`/fallback `sh`←`bash`, `javascript`+`js` alias/fallback none, needs `node`); `resolve_executable` picks whichever of the primary/fallback pair is actually on PATH via `vim.fn.executable`, warning via `vim.notify` (not erroring) when neither is — the same graceful-degradation contract `mep.treesitter.compiler.find` uses for a missing C compiler
- [x] Common header arguments: at least `:results` (value vs. output) and `:var` (inject buffer-local values as script arguments/prelude) — `:var name=value` (repeatable) becomes a prelude assignment in the target language's own syntax before the body (a bare number passes through as a literal, anything else becomes a quoted string — scalars only, no org-table/list injection, a deliberate scope-narrowing); `:results value` (recognized by substring match, so `:results value table` etc. still count) treats the block's **last non-blank line** as an expression and wraps it in the language's print function instead of running it as a plain statement — a documented simplification of real org-babel's per-language value-capture machinery (see "Notes on scope decisions" below for why), not meaningful for shell (a shell script's output already *is* its value, so `:results value` behaves identically to `output` there, matching real org-babel's own shell backend)
- [x] Tangle: extract one or all source blocks in a file out to real source files — `mep.org.babel.tangle_block` (the block at the cursor)/`tangle_buffer` (`<C-c>E`, every block in the buffer with a `:tangle target` header arg — real org-mode's own default of "don't tangle unless asked" applies: absent or `:tangle no` means skip); a relative target resolves against the buffer's own file directory (falling back to cwd for an unsaved buffer); multiple blocks sharing one target concatenate in document order, blank-line separated, matching real org-mode's own multi-chunk tangle behavior
- [x] **Explicitly deferred, likely indefinitely**: persistent sessions (a long-lived REPL per block), the full header-argument surface (`:session`, `:noweb`, `:cache`, etc.) — real org-babel's argument system is large enough to be its own multi-phase project

**Notes on scope decisions:**
- `:results value`'s "wrap the last non-blank line in print()" convention is a deliberate simplification of real org-babel's actual per-language value-capture machinery (which properly evaluates a block as an expression regardless of print statements). The alternative — real AST-level "evaluate as an expression" support per language — needs per-language parsing infrastructure this project doesn't have and isn't worth building for this feature's scope. The chosen convention still correctly supports `:var` + `:results value` together and multi-line setup before the value line, which covers the common real-world case (a short calculation/setup followed by a bare expression) reasonably well; write a bare expression as a block's last line to use it, not a `print`/`return` statement.
- No org-table/list literal injection for `:var` — only scalar (number/string) values. Real org-babel can inject a 2D table as a language-native array/list; this project's `:var` only ever produces a single scalar assignment.

**Real bugs/design problems found via testing** (busted + a real-headless-Neovim smoke test running real `lua`/`bash` subprocesses, per `CLAUDE.md`):
- The original keymap design bound execute/tangle to `<C-c><C-v><C-e>`/`<C-c><C-v><C-t>`, mirroring real org-babel's own Emacs `C-c C-v` prefix map. Confirmed empirically (via both synthetic `nvim_feedkeys` *and* `nvim_input`, the latter Neovim's own "simulates real user input" API — so this isn't a test-harness artifact) that **`<C-v>` cannot work as the first key of a Neovim Normal-mode mapping at all**: it always immediately enters Visual-Block mode before mapping resolution ever considers a longer sequence, no matter what's mapped. `<C-v>` later in a sequence works fine (`<C-x><C-v>` etc.), only the first-key position is affected. Since real org-babel's other alternate binding (`C-c C-c`) was already unavailable (dedicated to checkbox toggling since Phase 0), the keymaps were changed to `<C-c>e`/`<C-c>E`, mirroring this project's own `narrow`/`widen` (`<C-c>n`/`<C-c>N`) lowercase-acts-locally/uppercase-acts-globally convention instead.

## Phase 11 — org-export (done)

- [x] Export dispatcher/framework: `mep.org.export.parse`/`.parse_lines` parse a buffer (after resolving `#+INCLUDE:` and collecting `#+MACRO:` definitions) into a **flat**, ordered document model — a sequence of `headline`/`paragraph`/`list_item`/`src`/`block` elements, each carrying its own `level`/`depth` where relevant, rather than a nested tree of sections. Each backend reconstructs nesting itself as it emits output (a counter stack for `num:t` numbering, a list-nesting stack for `mep.org.export.html`'s `<ul>`/`<ol>`) — the same "flat list, not a tree" representation `mep.org.agenda`'s `collect_entries` already uses for headlines, kept the parser itself simple at the cost of a little backend-side bookkeeping. `mep.org.export.tokenize_inline` (shared by all three backends) turns paragraph/list-item/headline text into an ordered token stream (`text`/`bold`/`italic`/`underline`/`strike`/`code`/`verbatim`/`link`/`footnote`) — emphasis matching is a documented simplification of real org-mode's fuller pre/post border-character rules (content can't start with whitespace or the marker itself, matching common prose without the full boundary-character table). `dispatch_interactive` (`<C-c><C-e>`, matching real org-export-dispatch's own binding) prompts for a backend via `vim.ui.select` and writes to `default_path` (same directory/basename as the source file, with the backend's extension). `export_subtree` exports just the subtree at point (per-headline `:EXPORT_TITLE:` property support, see below) — real org tables aren't part of the model at all, not asked for by this phase's scope; a `|`-delimited line just falls through to plain paragraph text.
- [x] Plain text / ASCII backend (`mep.org.export.ascii`) — validated the framework first, per the roadmap's own suggestion. Matches real org-mode's own ascii backend on the one point that matters most: emphasis markers are left as literal characters (`*bold*` stays `*bold*`) rather than stripped, since plain text has no other way to signal emphasis. Level 1/2 headlines are underlined (`=`/`-`); deeper levels are plainly indented.
- [x] Markdown backend (`mep.org.export.markdown`) — `**bold**`, `_italic_` (single `*` avoided since it visually collides with `**bold**`), `<u>underline</u>` (Markdown's own documented inline-HTML escape hatch, not a mep.nvim invention — standard Markdown has no native underline), `~~strike~~`, `` `code`/`verbatim` `` (Markdown has only one inline code style, so both org constructs map to it), fenced ` ```lang ` code blocks, footnotes as `[^name]`/`[^name]: text` (Markdown's own standard footnote extension).
- [x] HTML backend (`mep.org.export.html`) — `<h1>`-`<h6>` (clamped), properly nested `<ul>`/`<ol>` reconstructed from the flat `list_item` stream via a depth stack, all text content HTML-escaped, a disabled `<input type="checkbox">` for checkbox items, footnotes as `<sup><a href="#fn-name">`/a bottom `<div id="footnotes">`.
- [x] Document-level export settings: `#+TITLE:`/`#+AUTHOR:`/`#+DATE:` (rendered by every backend); `#+OPTIONS: toc:nil num:nil` (table of contents and headline numbering, both **on** by default matching real org-mode — `num:t` assigns each headline a `"1.2.3"`-style `number` field the backends prefix onto its title, `toc:t` renders a contents list up front from the numbered headlines); per-subtree export via `:noexport:` (a headline so tagged, and its entire subtree, is dropped from the document — real org-mode's own default `org-export-exclude-tags`) and via `export_subtree`'s `:EXPORT_TITLE:` property override (the subtree headline's own title becomes the document title unless overridden; its descendants' levels are renormalized so the first child becomes level 1, matching real org-mode's own subtree-export behavior).
- [ ] **Likely deferred**: LaTeX/PDF backend (needs a LaTeX toolchain on PATH, similar external-tool tradeoff to the treesitter compiler — feasible but bigger scope than the other backends); ODT and other binary formats (much bigger scope, probably out of scope permanently)

## Phase 12 — Everything else (mostly done)

Lower-priority or higher-effort-per-value items; revisit after the above
phases land, or pull individual items forward if something specific is
needed sooner.

- [x] Footnotes (`mep.org.footnote`) — `[fn:name]` plain references, `[fn:name:inline def]`/`[fn::anonymous inline def]` inline definitions, and standalone `[fn:name] text` definition lines (read/written as a single line — real org-mode lets a definition's text continue onto following paragraphs; this project doesn't, the same "narrow slice" tradeoff `mep.org.clock`'s `:LOGBOOK:` state-change notes made). `<C-c><C-x>f` (real org-footnote-action's own binding) is context-sensitive: navigates from a reference to its definition (or back) via `goto_counterpart` when the cursor is on either half (`at_cursor`), otherwise inserts a new footnote interactively (prompts name — blank auto-numbers — then definition text; appended after the last existing definition, grouping them the way real org-mode's own "footnotes section" convention does).
- [x] Special blocks beyond src (`mep.org.block`) — generic `#+BEGIN_<kind> ... #+END_<kind>` parsing (quote/verse/example/center, or any other block name — including `src`, though `mep.org.babel` still owns execution/tangling of those), the same pure line-pattern style as `mep.org.babel.find_blocks` generalized off a hard-coded "src". Semantic handling lives in `mep.org.export`'s backends (quote → blockquote, verse → line-break-preserved, example → literal/preformatted, center → centered); a comment block (`#+BEGIN_COMMENT`) is dropped from export entirely.
- [x] Macros (`mep.org.macro`) — `#+MACRO: name value with $1 $2 ...` definitions, expanded at `{{{name}}}`/`{{{name(arg1,arg2)}}}` (a `\,`-escaped comma splits call arguments, matching real org-mode's own one escape). Wired into `mep.org.export`'s document-building pass: paragraph/list-item/headline text and quote/verse/center block bodies are macro-expanded, but not `src`/`example` content — matching real org-mode not expanding macros inside literal/code blocks. An unknown macro name is left untouched (`{{{typo}}}` stays visibly wrong) rather than silently vanishing; a missing argument position expands to empty.
- [x] `#+INCLUDE:` file inclusion (`mep.org.include`) — `#+INCLUDE: "path" [:lines "M-N"] [src lang]`, resolved recursively (depth-guarded, and cycle-detected via a `seen`-paths set so a self-referencing include can't hang) before `mep.org.export` builds its document model. A relative path resolves against the including file's own directory; an unreadable file or a detected cycle is left as the literal `#+INCLUDE:` line with a `vim.notify` warning rather than erroring.
- [x] org-id (`mep.org.id`) — `generate` (a random v4-UUID-shaped string, matching real org-id's own default `org-id-method`); `get_or_create` reads a headline's existing `:ID:` property or creates one (via `mep.org.property`); `find` looks up a headline by `:ID:` value (buffer-local only — no cross-file ID index, the same single-buffer scope `mep.org.refile` already documents for cross-file work waiting on a future phase). `<C-c><C-x>i` (no stock Emacs binding for `org-id-get-create`; this project gives it one for discoverability, consistent with `set_property`'s own `<C-c><C-x>` prefix).
- [x] Attachments (`mep.org.attach`) — real org-attach's own default ID-based method: a headline's attachment directory is `<file-dir>/<attach_dir>/<id[1:2]>/<id[3:]>/` (the 2/rest ID split is real org-attach's own collision-avoidance hashing trick, cheap here since the ID is already a random UUID), auto-creating an `:ID:` property via `mep.org.id` if the headline doesn't have one yet. `attach`/`attach_interactive` (`<C-c><C-a>`, prompts a source path) copy a file in by basename; `list` reads back what's there. `config.attach_dir` (default `"data"`, matching real org-attach's own `org-attach-directory` default) is the configurable root.
- [ ] **Likely permanently out of scope** (large, separately-scoped efforts in their own right): inline image rendering (needs a terminal image protocol), LaTeX fragment preview (needs external rendering + the same image-protocol problem), table formulas/spreadsheet mode, citations (`org-cite`), habit tracking, column view

## Notes on scope decisions already made (Phase 0)

- Promote/demote in Phase 0 affects only the current headline line, not
  its subtree — matches Emacs org-mode's plain `M-Left`/`M-Right`, not
  the subtree-wide variant. Subtree-wide promote/demote is Phase 1.
- Highlighting uses one color for all headline levels (not per-level, as
  real org-mode / orgmode.nvim do) because per-level requires a custom
  Lua query predicate that only exists if a plugin registers it — see
  `queries/org/highlights.scm`'s header comment. Revisit if we're willing
  to register a predicate ourselves (straightforward, just hasn't been
  needed yet).
- `mep.treesitter`'s parser installer (`git clone` + a detected C
  compiler) is the shared building block org-babel (Phase 10) should
  reuse for running code, and org-export's LaTeX backend (if attempted)
  would follow the same external-tool-with-graceful-degradation pattern.
- (Phase 3) The real `tree-sitter-org` grammar only parses an inactive
  `[2024-01-01 Mon]` timestamp as a proper `timestamp` node (and
  therefore highlights it) when it's alone on the planning line right
  after a headline — confirmed empirically against the compiled parser.
  An inactive timestamp embedded in ordinary body-text/paragraph content
  is *not* recognized as a timestamp node at all by this grammar version
  and falls back to plain-text tokens with no highlighting. Active
  `<...>` timestamps don't have this limitation in either position.
  `mep.org.timestamp`'s own parsing (used for insert/edit/adjust) is
  unaffected either way since it's pure line-pattern matching, not
  tree-sitter-based — this only affects *highlighting* of inline inactive
  timestamps in body text, a gap in the grammar itself, not something
  fixable from `queries/org/highlights.scm`.
- (Phase 5) `mep.org.org`'s `apply_fold` used to only ever *set*
  `foldmethod='expr'` when `fold=true`, never resetting it when
  `fold=false` — since `foldmethod` is window-local, a window that
  previously showed a `fold=true` buffer kept a stale `'expr'`
  foldmethod for a later buffer shown in the same window whose own
  config said `fold=false`. Found via the dev smoke test: a body line
  ended up inside a closed fold left over from an earlier buffer, and
  entering Visual mode on a line inside a closed fold makes Vim treat
  the whole fold as one unit for selection purposes (standard Vim
  behavior, not a bug) — which broke `mep.org.link.insert_interactive`'s
  visual-mode selection capture in a way that had nothing to do with the
  links code itself. Fixed by having `apply_fold` explicitly reset to
  Vim's own default (`'manual'`) when `fold=false`, so each buffer's own
  config always applies deterministically regardless of what a prior
  buffer left behind in that window; covered by a regression spec in
  `spec/mep/org/org_spec.lua`.
- (Phase 8) A Neovim buffer can never truly reach zero lines — even
  `nvim_buf_set_lines(buf, 0, N, false, {})` clearing every line leaves
  one fresh empty line behind to satisfy that invariant, confirmed
  empirically. `mep.org.capture`'s target-resolution logic has to know
  about this: a brand-new buffer for a not-yet-existing capture target
  file starts with this phantom blank line, and naively computing an
  "append after the last line" insertion point against it would leave a
  stray leading blank line ahead of the actual captured content. Fixed
  by detecting the phantom-line case (guarded on `filereadable` so a
  *real* file that happens to be a single blank line is left alone) and
  returning a range that *replaces* it instead of inserting after it.
- (Phase 8) `vim.cmd.startinsert()` called synchronously from deep inside
  a `mep.picker` `on_select` callback (itself invoked mid-`feedkeys`,
  when a user confirms a template in `capture_interactive`'s picker)
  does not reliably "stick" — confirmed empirically, including that it's
  still not in effect on the very next `vim.schedule`d tick when called
  synchronously at that point. Deferring the *whole* `startinsert()` +
  cursor-set through `vim.schedule` (letting the current key-processing
  cycle fully unwind first) fixes it — the standard, well-established
  Neovim idiom for "enter insert mode after opening a floating window
  from a callback," used by many real-world plugins for exactly this
  scenario. The dev smoke test needed its own adjustment to match: even
  with the fix, chaining multiple separate synthetic `nvim_feedkeys`
  calls in a headless script doesn't reliably preserve insert mode
  *across* those calls the way one continuous real keystroke stream
  would, so it drives the capture popup with `vim.wait()` after
  confirming a template (letting the deferred callback run) and then
  types via `A` (append-at-end-of-line) rather than assuming insert mode
  is still active — real interactive use isn't affected either way.

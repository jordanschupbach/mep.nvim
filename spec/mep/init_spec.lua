local mep = require('mep')
local sanity_config = require('mep.sanity.config')
local picker_config = require('mep.picker.config')
local icons_config = require('mep.icons.config')
local filetree_config = require('mep.filetree.config')
local dashboard_config = require('mep.dashboard.config')
local treesitter_config = require('mep.treesitter.config')
local treesitter_install = require('mep.treesitter.install')
local org_config = require('mep.org.config')
local whichkey_config = require('mep.whichkey.config')
local sidebar_config = require('mep.sidebar.config')
local notify_config = require('mep.notify.config')
local activitybar_config = require('mep.activitybar.config')
local lsp_config = require('mep.lsp.config')
local completion_config = require('mep.completion.config')
local url_config = require('mep.url.config')
local git_config = require('mep.git.config')
local window_config = require('mep.window.config')
local theme_config = require('mep.theme.config')
local chrome_config = require('mep.chrome.config')
local project_config = require('mep.project.config')
local ai_config = require('mep.ai.config')
local scratch_config = require('mep.scratch.config')
local symbols_config = require('mep.symbols.config')
local dap_config = require('mep.dap.config')
local docs_config = require('mep.docs.config')
local flashcards_config = require('mep.flashcards.config')
local help_config = require('mep.help.config')
local colorizer_config = require('mep.colorizer.config')
local leetcode_config = require('mep.leetcode.config')
local roam_config = require('mep.roam.config')
local run_config = require('mep.run.config')
local repl_config = require('mep.repl.config')
local snippet_config = require('mep.snippet.config')
local todoscan_config = require('mep.todoscan.config')
local zen_config = require('mep.zen.config')

-- Every library's config module, keyed by the same name `mep.setup()`'s
-- own `opts.<name>` uses — driven by a table (not one named local per
-- library) specifically so `before_each`/`after_each` below stay at a
-- constant 2 upvalues each as more libraries are added, rather than
-- growing by one per library: Lua caps a function at 60 upvalues, and
-- the previous one-named-local-per-library shape actually hit that
-- ceiling once this list passed ~28 entries.
local CONFIG_MODULES = {
  { name = 'sanity', mod = sanity_config },
  { name = 'picker', mod = picker_config },
  { name = 'icons', mod = icons_config },
  { name = 'filetree', mod = filetree_config },
  { name = 'dashboard', mod = dashboard_config },
  { name = 'treesitter', mod = treesitter_config },
  { name = 'org', mod = org_config },
  { name = 'whichkey', mod = whichkey_config },
  { name = 'sidebar', mod = sidebar_config },
  { name = 'notify', mod = notify_config },
  { name = 'activitybar', mod = activitybar_config },
  { name = 'lsp', mod = lsp_config },
  { name = 'completion', mod = completion_config },
  { name = 'url', mod = url_config },
  { name = 'git', mod = git_config },
  { name = 'window', mod = window_config },
  { name = 'theme', mod = theme_config },
  { name = 'chrome', mod = chrome_config },
  { name = 'project', mod = project_config },
  { name = 'ai', mod = ai_config },
  { name = 'scratch', mod = scratch_config },
  { name = 'symbols', mod = symbols_config },
  { name = 'dap', mod = dap_config },
  { name = 'docs', mod = docs_config },
  { name = 'flashcards', mod = flashcards_config },
  { name = 'help', mod = help_config },
  { name = 'colorizer', mod = colorizer_config },
  { name = 'leetcode', mod = leetcode_config },
  { name = 'roam', mod = roam_config },
  { name = 'run', mod = run_config },
  { name = 'repl', mod = repl_config },
  { name = 'snippet', mod = snippet_config },
  { name = 'todoscan', mod = todoscan_config },
  { name = 'zen', mod = zen_config },
}

describe('mep (top-level setup fan-out)', function()
  local saved_leader, saved_localleader
  local saved_options = {}
  local orig_install_all, orig_install
  local orig_notify
  local orig_lsp_config, orig_lsp_enable, orig_diag_config
  local orig_jobstart

  before_each(function()
    saved_leader = vim.g.mapleader
    saved_localleader = vim.g.maplocalleader
    for _, entry in ipairs(CONFIG_MODULES) do
      saved_options[entry.name] = vim.deepcopy(entry.mod.options)
    end
    orig_notify = vim.notify

    -- mep.git.setup()'s default enable=true attaches mep.git.gutter to
    -- every already-loaded, file-backed buffer, which would otherwise
    -- shell out to a *real* `git show` for any such buffer that happens
    -- to sit inside a real git repo (this project's own checkout
    -- included) — never something this shared-process test file should
    -- risk (same reasoning as the vim.lsp.config/enable stubs below).
    orig_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 1 -- a fake, never-resolving job id; nothing here awaits it
    end

    -- mep.treesitter.setup()'s default ensure_installed=true, and
    -- mep.org's default highlight=true (for any already-'org'-filetype
    -- buffer), would otherwise try to git-clone/compile real parsers on
    -- every mep.setup() call in this file; both install paths are fully
    -- covered by their own specs, so they're stubbed out here
    -- unconditionally.
    orig_install_all = treesitter_install.install_all
    orig_install = treesitter_install.install
    treesitter_install.install_all = function(_, _, on_done)
      if on_done then
        on_done({ installed = {}, skipped = {}, failed = {} })
      end
    end
    treesitter_install.install = function(_, on_done)
      if on_done then
        on_done(true)
      end
    end

    -- mep.lsp.setup()'s default enable=true would otherwise call the
    -- *real* vim.lsp.enable() for any curated server whose cmd happens
    -- to genuinely be on PATH in whatever environment this suite runs
    -- in — never something this shared-process test file should risk;
    -- mocked the same way mep/lsp/lsp_spec.lua mocks it for its own,
    -- more targeted tests.
    orig_lsp_config = vim.lsp.config
    orig_lsp_enable = vim.lsp.enable
    orig_diag_config = vim.diagnostic.config
    vim.lsp.config = function() end
    vim.lsp.enable = function() end
    vim.diagnostic.config = function() end
  end)

  after_each(function()
    -- mep.whichkey.setup() binds a real, global keymap per trigger
    -- (`<leader>` by default); Neovim resolves that `<leader>` against
    -- whatever `mapleader` is current *when the mapping is defined*, so
    -- this has to run — using the literal `'<leader>'` string, letting
    -- Neovim itself resolve it — *before* `mapleader` is restored below,
    -- while it's still whatever value this test's own mep.setup() left
    -- it as. Otherwise the mapping leaks into some other spec file
    -- sharing this same busted run.
    pcall(vim.keymap.del, 'n', '<leader>')
    -- mep.git.setup() binds real, global toggle-sidebar keymaps the same
    -- way (<leader>gg/<leader>gG by default).
    pcall(vim.keymap.del, 'n', '<leader>gg')
    pcall(vim.keymap.del, 'n', '<leader>gG')
    -- mep.symbols.setup() binds a real, global toggle keymap the same
    -- way (<leader>ll by default).
    pcall(vim.keymap.del, 'n', '<leader>ll')
    -- mep.dap.setup() binds real, global keymaps for every configured
    -- action (10 by default, <leader>d*) — mep.dap.keymaps.bind's own
    -- unconditional global-keymap posture (debugging isn't filetype/
    -- LSP-attach-gated the way mep.lsp's own keymaps are).
    for _, lhs_list in pairs(dap_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.docs.setup() binds real, global keymaps the same way
    -- (<leader>ld/<leader>lD by default).
    for _, lhs_list in pairs(docs_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.flashcards.setup() binds a real, global keymap the same way
    -- (<leader>fr by default).
    for _, lhs_list in pairs(flashcards_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.help.setup() binds a real, global keymap the same way
    -- (<leader>? by default).
    for _, lhs_list in pairs(help_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.leetcode.setup() binds a real, global keymap the same way
    -- (<leader>lc by default).
    for _, lhs_list in pairs(leetcode_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.roam.setup() binds real, global keymaps the same way
    -- (<leader>rf/<leader>rb/<leader>rt/<leader>rc by default).
    for _, lhs_list in pairs(roam_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.run.setup() binds a real, global keymap the same way
    -- (<leader>xr by default).
    for _, lhs_list in pairs(run_config.defaults.keymaps) do
      for _, lhs in ipairs(lhs_list) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.repl.setup() binds real, global keymaps the same way
    -- (<leader>sl/<leader>ss (visual)/<leader>sb/<leader>sr by
    -- default) — send_selection is visual-mode, the rest normal.
    pcall(vim.keymap.del, 'x', '<leader>ss')
    for _, name in ipairs({ 'send_line', 'send_buffer', 'jump_to_repl' }) do
      for _, lhs in ipairs(repl_config.defaults.keymaps[name]) do
        pcall(vim.keymap.del, 'n', lhs)
      end
    end
    -- mep.snippet.setup()'s default tab_keymap=true binds real, global
    -- insert-mode <Tab>/<S-Tab> keymaps.
    pcall(vim.keymap.del, 'i', '<Tab>')
    pcall(vim.keymap.del, 'i', '<S-Tab>')

    vim.g.mapleader = saved_leader
    vim.g.maplocalleader = saved_localleader
    for _, entry in ipairs(CONFIG_MODULES) do
      entry.mod.options = saved_options[entry.name]
    end
    require('mep.scratch').reset()
    treesitter_install.install_all = orig_install_all
    treesitter_install.install = orig_install
    require('mep.filetree').reset()
    require('mep.dashboard').reset() -- undo any auto-open autocmds this test registered
    -- mep.activitybar.setup() hooks vim.notify via mep.notify.install()
    -- and may have created (closed) bar/panel mep.sidebar instances —
    -- mep.notify._reset() undoes the hook (and any real toast popups a
    -- test's own vim.notify() call left open); mep.activitybar._reset()
    -- undoes its own bar/panel instances. Both need a clean slate for
    -- later tests and other spec files sharing this busted run.
    require('mep.activitybar')._reset()
    require('mep.notify')._reset()
    vim.notify = orig_notify
    vim.lsp.config = orig_lsp_config
    vim.lsp.enable = orig_lsp_enable
    vim.diagnostic.config = orig_diag_config
    -- mep.completion.setup() registers a real, global TextChangedI
    -- autocmd plus an insert-mode trigger keymap (<C-Space> by default)
    -- — engine.disable() is the module's own correct teardown for both.
    require('mep.completion.engine').disable()
    -- mep.url.setup() binds real, global gx/gX keymaps.
    pcall(vim.keymap.del, 'n', 'gx')
    pcall(vim.keymap.del, 'n', 'gX')
    -- mep.ai.setup() binds real, global send/cancel keymaps (`gl`/
    -- `<leader>ax` by default) — same reasoning as every other library's
    -- own global keymaps above; left unbound if a leaked mapping from an
    -- earlier test already deleted them, hence `pcall`.
    pcall(vim.keymap.del, 'n', 'gl')
    pcall(vim.keymap.del, 'n', '<leader>ax')
    -- mep.treesitter.setup()/mep.org.setup()/mep.lsp.setup() each
    -- register a real, global autocmd (FileType/FileType/LspAttach); only
    -- a later setup() call clears its own (recreates the group with
    -- clear=true), so drop all three explicitly or they fire for any
    -- buffer/client any later spec (in any file) hands them.
    pcall(vim.api.nvim_del_augroup_by_name, 'MepTreesitter')
    pcall(vim.api.nvim_del_augroup_by_name, 'MepOrg')
    pcall(vim.api.nvim_del_augroup_by_name, 'MepLsp')
    -- mep.git.setup()'s default enable=true registers its own real,
    -- global BufEnter/BufReadPost autocmd (mep.git.gutter's own
    -- MepGit) plus per-buffer state for anything it attached —
    -- gutter.disable() is that module's own correct teardown for both.
    require('mep.git.gutter').disable()
    vim.fn.jobstart = orig_jobstart
    -- mep.window.setup()'s default manual.enable=true binds a real,
    -- global keymap per manual-layout action (split/focus/resize/move/
    -- tab-cycle/remove, 15 in total by default) plus a real, global
    -- BufWinEnter/WinClosed augroup — panes.disable() is that module's
    -- own correct teardown for both.
    require('mep.window.panes').disable()
    -- mep.theme.setup() binds a real, global picker keymap
    -- (<leader>ut by default) and mutates real, global highlight
    -- groups (applying its default theme) — the keymap needs the same
    -- explicit cleanup as every other library's own global keymaps
    -- above; the highlight mutation is accepted as-is, the same as any
    -- other spec file that calls mep.theme.apply() directly (see that
    -- library's own theme_spec.lua header comment) — a colorscheme
    -- change has no clean "undo" and every other test that cares about
    -- specific highlight values already re-establishes its own state
    -- immediately before asserting on it.
    require('mep.theme')._reset()
    for _, lhs in ipairs(theme_config.defaults.keymaps.picker) do
      pcall(vim.keymap.del, 'n', lhs)
    end
    -- mep.chrome.setup()'s default border.enable=true registers a real,
    -- global WinEnter/VimEnter augroup (mep.chrome.border's own
    -- MepChromeBorder) and may have mutated real windows' 'winhighlight'
    -- — chrome._reset() is the library's own correct teardown for that
    -- plus statusline/winbar/tabline/statuscolumn/hover/click state.
    require('mep.chrome')._reset()
    -- mep.dap.setup() itself only binds keymaps, but a test could have
    -- gone on to actually use the library (launch/toggle breakpoints/
    -- open the sidebar or console) — reset every stateful submodule the
    -- same way mep.activitybar/mep.notify/mep.theme/mep.chrome do above.
    require('mep.dap.session')._reset()
    require('mep.dap.sidebar')._reset()
    require('mep.dap.repl')._reset()
    require('mep.dap.breakpoints').clear_all()
    -- mep.flashcards.setup() itself only binds a keymap, but a test
    -- could go on to actually open a review session.
    require('mep.flashcards.review')._reset()
    -- mep.roam.setup() itself only binds keymaps, but a test could go
    -- on to actually open the backlinks panel.
    require('mep.roam.backlinks')._reset()
    -- mep.colorizer.setup()'s unconditional enable() attaches to every
    -- already-loaded buffer (real, global BufEnter/BufReadPost augroup
    -- plus one augroup/timer per attached buffer) — _reset() is that
    -- module's own correct teardown for all of it.
    require('mep.colorizer')._reset()
    -- mep.repl.setup() registers a real, global TermOpen augroup, and a
    -- test could go on to actually start a REPL session.
    require('mep.repl')._reset()
    -- mep.snippet.setup() itself only binds keymaps, but a test could go
    -- on to actually expand a snippet, leaving a session active.
    require('mep.snippet.session')._reset()
    require('mep.snippet.registry')._reset()
    -- mep.todoscan.setup()'s default highlight=true attaches to every
    -- already-loaded buffer (real, global BufEnter/BufReadPost augroup
    -- plus one augroup/timer per attached buffer) — _reset() is that
    -- submodule's own correct teardown for all of it.
    require('mep.todoscan.highlight')._reset()
    -- mep.zen.setup() itself only stores config, but a test could go on
    -- to actually toggle zen mode.
    require('mep.zen')._reset()
  end)

  it('setup({}) applies each library\'s defaults', function()
    mep.setup({})
    assert.are.equal(' ', vim.g.mapleader)
    assert.are.equal(20, picker_config.options.debounce_ms.static)
    assert.are.equal('nerd_font', icons_config.options.style)
    assert.are.equal(30, filetree_config.options.width)
    assert.is_true(dashboard_config.options.auto_open)
    assert.is_true(treesitter_config.options.highlight)
    assert.is_true(org_config.options.highlight)
    assert.are.equal('scratch', scratch_config.options.name)
  end)

  it('setup() with no argument at all does not error', function()
    assert.has_no.errors(function()
      mep.setup()
    end)
    assert.are.equal(' ', vim.g.mapleader)
  end)

  it('forwards opts.sanity to mep.sanity.setup', function()
    mep.setup({ sanity = { leader = ';' } })
    assert.are.equal(';', vim.g.mapleader)
  end)

  it('forwards opts.picker to mep.picker.setup, deep-merged', function()
    mep.setup({ picker = { debounce_ms = { static = 3 } } })
    assert.are.equal(3, picker_config.options.debounce_ms.static)
    assert.are.equal(120, picker_config.options.debounce_ms.dynamic) -- untouched
  end)

  it('forwards opts.icons to mep.icons.setup', function()
    mep.setup({ icons = { style = 'ascii' } })
    assert.are.equal('ascii', icons_config.options.style)
  end)

  it('forwards opts.filetree to mep.filetree.setup, deep-merged', function()
    mep.setup({ filetree = { width = 42 } })
    assert.are.equal(42, filetree_config.options.width)
    assert.is_false(filetree_config.options.show_hidden) -- untouched
  end)

  it('forwards opts.dashboard to mep.dashboard.setup, deep-merged', function()
    mep.setup({ dashboard = { auto_open = false } })
    assert.is_false(dashboard_config.options.auto_open)
    assert.are.equal('intro', dashboard_config.options.content) -- untouched
  end)

  it('forwards opts.treesitter to mep.treesitter.setup, deep-merged', function()
    mep.setup({ treesitter = { ensure_installed = false } })
    assert.is_false(treesitter_config.options.ensure_installed)
    assert.is_true(treesitter_config.options.highlight) -- untouched
  end)

  it('forwards opts.org to mep.org.setup, deep-merged', function()
    mep.setup({ org = { fold = false } })
    assert.is_false(org_config.options.fold)
    assert.are.same({ 'TODO', 'DONE' }, org_config.options.todo_keywords) -- untouched
  end)

  it('forwards opts.whichkey to mep.whichkey.setup, deep-merged', function()
    mep.setup({ whichkey = { triggers = { '<leader>', ',' } } })
    assert.are.same({ '<leader>', ',' }, whichkey_config.options.triggers)
    assert.are.same({ 'n' }, whichkey_config.options.modes) -- untouched
    pcall(vim.keymap.del, 'n', ',')
  end)

  it('forwards opts.sidebar to mep.sidebar.setup, deep-merged', function()
    mep.setup({ sidebar = { width = 50 } })
    assert.are.equal(50, sidebar_config.options.width)
    assert.are.equal('right', sidebar_config.options.position) -- untouched
  end)

  it('forwards opts.activitybar to mep.activitybar.setup, deep-merged', function()
    mep.setup({ activitybar = { panel_width = 60 } })
    assert.are.equal(60, activitybar_config.options.panel_width)
    assert.are.equal('right', activitybar_config.options.position) -- untouched
  end)

  it('forwards opts.lsp to mep.lsp.setup, deep-merged', function()
    mep.setup({ lsp = { completion = false } })
    assert.is_false(lsp_config.options.completion)
    assert.is_true(lsp_config.options.enable) -- untouched
  end)

  it('forwards opts.completion to mep.completion.setup, deep-merged', function()
    mep.setup({ completion = { min_chars = 3 } })
    assert.are.equal(3, completion_config.options.min_chars)
    assert.are.same({ 'lsp', 'buffer', 'path', 'snippet' }, completion_config.options.sources) -- untouched
  end)

  it('forwards opts.url to mep.url.setup, deep-merged', function()
    mep.setup({ url = { keymaps = { open = { '<leader>gx' } } } })
    assert.are.same({ '<leader>gx' }, url_config.options.keymaps.open)
    assert.are.same({ 'gX' }, url_config.options.keymaps.pick) -- untouched
    pcall(vim.keymap.del, 'n', '<leader>gx')
  end)

  it('forwards opts.git to mep.git.setup, deep-merged', function()
    mep.setup({ git = { debounce_ms = 500 } })
    assert.are.equal(500, git_config.options.debounce_ms)
    assert.is_true(git_config.options.enable) -- untouched
  end)

  it('forwards opts.window to mep.window.setup, deep-merged', function()
    mep.setup({ window = { manual = { resize_step = 9 } } })
    assert.are.equal(9, window_config.options.manual.resize_step)
    assert.is_true(window_config.options.manual.enable) -- untouched
  end)

  it('forwards opts.theme to mep.theme.setup, deep-merged', function()
    mep.setup({ theme = { default = 'nord' } })
    assert.are.equal('nord', theme_config.options.default)
    assert.are.equal('nord', require('mep.theme').current())
    assert.is_true(theme_config.options.apply_on_setup) -- untouched
  end)

  it('forwards opts.chrome to mep.chrome.setup, deep-merged', function()
    mep.setup({ chrome = { statusline = { enable = true } } })
    assert.is_true(chrome_config.options.statusline.enable)
    assert.is_true(chrome_config.options.border.enable) -- untouched
  end)

  it('forwards opts.project to mep.project.setup, deep-merged', function()
    mep.setup({ project = { persist_path = '/tmp/mep-init-spec-projects.json' } })
    assert.are.equal('/tmp/mep-init-spec-projects.json', project_config.options.persist_path)
    assert.are.same({ 'README.org', 'README.md' }, project_config.options.readme_names) -- untouched
  end)

  it('forwards opts.scratch to mep.scratch.setup, deep-merged', function()
    mep.setup({ scratch = { filetype = 'markdown' } })
    assert.are.equal('markdown', scratch_config.options.filetype)
    assert.are.equal('scratch', scratch_config.options.name) -- untouched
  end)

  it('forwards opts.ai to mep.ai.setup, deep-merged', function()
    mep.setup({ ai = { provider = 'openai', providers = { openai = { model = 'gpt-4o-mini' } } } })
    assert.are.equal('openai', ai_config.options.provider)
    assert.are.equal('gpt-4o-mini', ai_config.options.providers.openai.model)
    assert.are.equal('https://api.openai.com/v1/chat/completions', ai_config.options.providers.openai.endpoint) -- untouched
  end)

  it('forwards opts.notify to mep.notify.setup, deep-merged', function()
    mep.setup({ notify = { position = 'bottom-left', max_entries = 50 } })
    assert.are.equal('bottom-left', notify_config.options.position)
    assert.are.equal(50, notify_config.options.max_entries)
    assert.are.equal('rounded', notify_config.options.border) -- untouched
  end)

  it('setup({}) installs the mep.notify vim.notify hook', function()
    mep.setup({})
    assert.are_not.equal(orig_notify, vim.notify)
  end)

  it('does not require every library key to be present', function()
    assert.has_no.errors(function()
      mep.setup({ sanity = { leader = '\\' } })
    end)
  end)

  it('exposes every library lazily via the same modules require() returns', function()
    assert.are.equal(require('mep.core'), mep.core)
    assert.are.equal(require('mep.sanity'), mep.sanity)
    assert.are.equal(require('mep.dashboard'), mep.dashboard)
    assert.are.equal(require('mep.icons'), mep.icons)
    assert.are.equal(require('mep.filetree'), mep.filetree)
    assert.are.equal(require('mep.treesitter'), mep.treesitter)
    assert.are.equal(require('mep.org'), mep.org)
    assert.are.equal(require('mep.picker'), mep.picker)
    assert.are.equal(require('mep.whichkey'), mep.whichkey)
    assert.are.equal(require('mep.sidebar'), mep.sidebar)
    assert.are.equal(require('mep.notify'), mep.notify)
    assert.are.equal(require('mep.activitybar'), mep.activitybar)
    assert.are.equal(require('mep.lsp'), mep.lsp)
    assert.are.equal(require('mep.completion'), mep.completion)
    assert.are.equal(require('mep.url'), mep.url)
    assert.are.equal(require('mep.git'), mep.git)
    assert.are.equal(require('mep.window'), mep.window)
    assert.are.equal(require('mep.theme'), mep.theme)
    assert.are.equal(require('mep.chrome'), mep.chrome)
    assert.are.equal(require('mep.project'), mep.project)
    assert.are.equal(require('mep.ai'), mep.ai)
    assert.are.equal(require('mep.scratch'), mep.scratch)
    assert.are.equal(require('mep.version'), mep.version)
  end)
end)

if vim.g.loaded_mep then
  return
end
vim.g.loaded_mep = true

if vim.fn.has('nvim-0.9') == 0 then
  vim.notify('mep.nvim requires Neovim >= 0.9', vim.log.levels.ERROR)
  return
end

local function set_highlights()
  vim.api.nvim_set_hl(0, 'MepMatch', { link = 'Search', default = true })
  vim.api.nvim_set_hl(0, 'MepPreviewLine', { link = 'CursorLine', default = true })
  -- Not 'CursorLine': the picker's results window is a float, whose
  -- background is 'NormalFloat' (bg_float, which falls back to bg_alt
  -- under mep's own themes) — and 'CursorLine' is also just 'bg_alt',
  -- so linking there makes the "selected" row render in the exact same
  -- color as the rest of the window, i.e. invisible. 'PmenuSel' (same
  -- group Neovim's own completion popup uses for its selected entry) is
  -- always a strong, reversed-color highlight, so it stays visible
  -- regardless of what the surrounding float's background resolves to.
  vim.api.nvim_set_hl(0, 'MepPickerSelected', { link = 'PmenuSel', default = true })
  vim.api.nvim_set_hl(0, 'MepIconFile', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'MepIconDirectory', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'MepFiletreeDirectory', { link = 'Directory', default = true })
  vim.api.nvim_set_hl(0, 'MepFiletreeHint', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'MepDashboardLogo', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'MepDashboardVersion', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'MepDashboardCommand', { link = 'Special', default = true })
  vim.api.nvim_set_hl(0, 'MepDashboardLink', { link = 'Underlined', default = true })
  vim.api.nvim_set_hl(0, 'MepSidebarTitle', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'MepSidebarSectionHeader', { link = 'Statement', default = true })
  -- mep.notify's own severity colors — toast borders/headers and
  -- history-panel entries alike, all keyed by the same four groups so
  -- overriding one recolors both. Linked to Neovim's own Diagnostic*
  -- groups by default (same reasoning as MepGit*/MepWindowTab* above:
  -- reapplied on every real `:colorscheme` change, not just once).
  vim.api.nvim_set_hl(0, 'MepNotifyError', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'MepNotifyWarn', { link = 'DiagnosticWarn', default = true })
  vim.api.nvim_set_hl(0, 'MepNotifyInfo', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'MepNotifyDebug', { link = 'DiagnosticHint', default = true })
  -- mep.git.gutter.enable() also defines these itself (so the gutter
  -- still looks right even without this plugin/ file — e.g. under the
  -- busted/nlua test harness, which never loads it) — repeated here too
  -- so, like every other Mep* group, they get reapplied on a real
  -- `:colorscheme` change instead of only once at `enable()` time.
  vim.api.nvim_set_hl(0, 'MepGitAdd', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'MepGitChange', { link = 'DiffChange', default = true })
  vim.api.nvim_set_hl(0, 'MepGitDelete', { link = 'DiffDelete', default = true })
  vim.api.nvim_set_hl(0, 'MepGitChangeDelete', { link = 'DiffChange', default = true })
  -- mep.window.panes.enable() also defines these itself, same reasoning
  -- as the MepGit* groups above.
  vim.api.nvim_set_hl(0, 'MepWindowTab', { link = 'TabLine', default = true })
  vim.api.nvim_set_hl(0, 'MepWindowTabActive', { link = 'TabLineSel', default = true })
  -- mep.chrome.render's own default "no highlight override" group, used
  -- to end a widget's %#hl#...%# span; MepChromeBorderActive is mep.
  -- chrome.border's active-window edge color (magenta, per the
  -- original request) — both re-applied here on every real
  -- `:colorscheme` change, same reasoning as every other Mep* group.
  vim.api.nvim_set_hl(0, 'MepChromeNormal', { link = 'StatusLine', default = true })
  vim.api.nvim_set_hl(0, 'MepChromeBorderActive', { fg = '#ff00ff', bold = true, default = true })
  -- mep.org.blockhl/mep.org.resultshl also define these themselves (same
  -- reasoning as the MepGit*/MepWindowTab* groups above) — but only when
  -- an org buffer actually activates, which a `:colorscheme`/`mep.theme.
  -- apply()` switch doesn't re-trigger on its own; without repeating them
  -- here too, both groups would go undefined (wiped by `hi clear`, per
  -- `mep.theme.engine.apply`'s own comment on why only centrally-listed
  -- groups survive that automatically) the moment a *different* theme is
  -- applied, until whatever org buffer is open gets reopened/re-set-up.
  vim.api.nvim_set_hl(0, 'MepOrgSrcBlock', { link = 'CursorLine', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgResultsBlock', { link = 'Constant', default = true })
  -- mep.org.headlinehl's own `M.LINKS`, repeated here for the same
  -- ColorScheme-survival reason as the two lines just above — keep in
  -- sync with that table by hand if it ever changes.
  vim.api.nvim_set_hl(0, 'MepOrgHeadline1', { link = 'Function', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgHeadline2', { link = 'Define', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgHeadline3', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgHeadline4', { link = 'DiagnosticHint', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgHeadline5', { link = 'Keyword', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgHeadline6', { link = 'Type', default = true })
  -- mep.org.todohl's own `M.LINKS`, repeated here for the same
  -- ColorScheme-survival reason as the MepOrgHeadlineN groups above —
  -- keep in sync with that table by hand if it ever changes.
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword1', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword2', { link = 'DiagnosticOk', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword3', { link = 'DiagnosticWarn', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword4', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword5', { link = 'DiagnosticHint', default = true })
  vim.api.nvim_set_hl(0, 'MepOrgTodoKeyword6', { link = 'Type', default = true })
end
set_highlights()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('MepHighlights', { clear = true }),
  callback = set_highlights,
})

vim.api.nvim_create_user_command('MepFindFiles', function()
  require('mep.picker').find_files()
end, { desc = 'mep.nvim: fuzzy-find files in the project' })

vim.api.nvim_create_user_command('MepLiveGrep', function()
  require('mep.picker').live_grep()
end, { desc = 'mep.nvim: live grep the project (requires rg)' })

vim.api.nvim_create_user_command('MepBufferSearch', function()
  require('mep.picker').buffer_search()
end, { desc = 'mep.nvim: fuzzy-find lines in the current buffer' })

vim.api.nvim_create_user_command('MepBuffers', function()
  require('mep.picker').buffers()
end, { desc = 'mep.nvim: fuzzy-find among open buffers' })

vim.api.nvim_create_user_command('MepScratch', function()
  require('mep.scratch').open()
end, { desc = 'mep.nvim: open the (single, persistent) scratch buffer in the current window' })

vim.api.nvim_create_user_command('MepProjects', function()
  require('mep.project').picker()
end, { desc = 'mep.nvim: fuzzy-find and switch between saved projects (<C-a> in the picker adds the cwd)' })

vim.api.nvim_create_user_command('MepFileTreeToggle', function()
  require('mep.filetree').toggle()
end, { desc = 'mep.nvim: toggle the file tree sidebar' })

vim.api.nvim_create_user_command('MepFileTreeRefresh', function()
  require('mep.filetree').refresh()
end, { desc = 'mep.nvim: re-scan the file tree' })

vim.api.nvim_create_user_command('MepDashboard', function()
  require('mep.dashboard').open()
end, { desc = 'mep.nvim: show the dashboard in the current window' })

vim.api.nvim_create_user_command('MepTreesitterInstall', function(cmd_opts)
  local name = cmd_opts.args
  require('mep.treesitter').install(name, function(ok, err)
    if ok then
      vim.notify('mep.treesitter: installed ' .. name, vim.log.levels.INFO)
    else
      vim.notify('mep.treesitter: failed to install ' .. name .. (err and (': ' .. err) or ''), vim.log.levels.ERROR)
    end
  end)
end, {
  nargs = 1,
  complete = function()
    return require('mep.treesitter.parsers').names()
  end,
  desc = 'mep.nvim: install one tree-sitter parser',
})

vim.api.nvim_create_user_command('MepActivityBarToggle', function()
  require('mep.activitybar').toggle_bar()
end, { desc = 'mep.nvim: toggle the activity bar' })

vim.api.nvim_create_user_command('MepNotifications', function()
  require('mep.activitybar').toggle_panel('notifications')
end, { desc = 'mep.nvim: toggle the notifications panel (in the activity bar)' })

vim.api.nvim_create_user_command('MepNotifyPanel', function()
  require('mep.notify').toggle()
end, { desc = 'mep.nvim: toggle the standalone notification history panel (independent of mep.activitybar)' })

vim.api.nvim_create_user_command('MepNotifyClear', function()
  require('mep.notify').clear()
end, { desc = 'mep.nvim: clear all notification history' })

vim.api.nvim_create_user_command('MepNotifyDismiss', function()
  require('mep.notify').popup.dismiss_all()
end, { desc = 'mep.nvim: dismiss every currently-visible notification popup (history is untouched)' })

vim.api.nvim_create_user_command('MepTodo', function()
  require('mep.activitybar').toggle_panel('todo')
end, { desc = 'mep.nvim: toggle the todo panel' })

vim.api.nvim_create_user_command('MepTests', function()
  require('mep.activitybar').toggle_panel('tests')
end, { desc = 'mep.nvim: toggle the tests panel' })

vim.api.nvim_create_user_command('MepTestsRun', function()
  require('mep.activitybar').tests.run()
end, { desc = 'mep.nvim: run tests (mep.activitybar.tests)' })

vim.api.nvim_create_user_command('MepGitPanel', function()
  require('mep.activitybar').toggle_panel('git')
end, { desc = 'mep.nvim: toggle the git panel (in the activity bar)' })

vim.api.nvim_create_user_command('MepGitToggle', function()
  require('mep.git').sidebar.toggle_dock()
end, { desc = 'mep.nvim: toggle the git panel (docked, edge-anchored)' })

vim.api.nvim_create_user_command('MepGitSplit', function()
  require('mep.git').sidebar.toggle_split()
end, { desc = 'mep.nvim: toggle the git panel (as a split in the current window)' })

vim.api.nvim_create_user_command('MepWindowLayout', function(cmd_opts)
  require('mep.window').auto.apply(cmd_opts.args)
end, {
  nargs = 1,
  complete = function()
    return require('mep.window.auto').names
  end,
  desc = 'mep.nvim: rebuild the current tabpage into an automatic layout (master_left/right/top/bottom, vertical, horizontal, square, spiral)',
})

vim.api.nvim_create_user_command('MepTheme', function(cmd_opts)
  require('mep.theme').apply(cmd_opts.args)
end, {
  nargs = 1,
  complete = function()
    return require('mep.theme').list()
  end,
  desc = 'mep.nvim: apply a theme',
})

vim.api.nvim_create_user_command('MepThemePicker', function()
  require('mep.theme').picker()
end, { desc = 'mep.nvim: open the fuzzy theme picker (live preview, Enter commits, Escape reverts)' })

vim.api.nvim_create_user_command('MepLspInfo', function()
  if type(vim.lsp.get_clients) ~= 'function' then
    vim.notify('mep.lsp: vim.lsp.get_clients unavailable (needs Neovim 0.11+)', vim.log.levels.WARN)
    return
  end
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify('mep.lsp: no client attached to this buffer', vim.log.levels.INFO)
    return
  end
  local lines = {}
  for _, client in ipairs(clients) do
    lines[#lines + 1] = string.format('%s (id %d): %s', client.name, client.id, table.concat(client.config.cmd or {}, ' '))
  end
  vim.notify('mep.lsp: attached clients\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
end, { desc = 'mep.nvim: show LSP clients attached to the current buffer' })

vim.api.nvim_create_user_command('MepOpenUrl', function()
  require('mep.url').open_at_cursor(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
end, { desc = 'mep.nvim: open the URL under the cursor' })

vim.api.nvim_create_user_command('MepUrls', function()
  require('mep.url').pick(vim.api.nvim_get_current_buf())
end, { desc = 'mep.nvim: list every URL in the buffer and open one' })

vim.api.nvim_create_user_command('MepTreesitterInstallAll', function()
  require('mep.treesitter').install_all(nil, nil, function(result)
    vim.notify(
      string.format(
        'mep.treesitter: install complete — %d installed, %d already present, %d failed',
        #result.installed,
        #result.skipped,
        vim.tbl_count(result.failed)
      ),
      vim.log.levels.INFO
    )
  end)
end, { desc = 'mep.nvim: install every parser in the curated registry' })

vim.api.nvim_create_user_command('MepAiSend', function()
  require('mep.ai').send()
end, { desc = 'mep.nvim: send the current buffer to the configured LLM, streaming the response in at the cursor' })

vim.api.nvim_create_user_command('MepAiSendSelection', function(cmd_opts)
  require('mep.ai').send_selection(cmd_opts.line1, cmd_opts.line2)
end, {
  range = true,
  desc = 'mep.nvim: send the given line range to the LLM as an editing agent, replacing it in place (usable as :\'<,\'>MepAiSendSelection)',
})

vim.api.nvim_create_user_command('MepAiSendSelectionPrompt', function(cmd_opts)
  require('mep.ai.popup').prompt('mep.ai: instructions', function(instructions)
    require('mep.ai').send_selection(cmd_opts.line1, cmd_opts.line2, { instructions = instructions })
  end)
end, {
  range = true,
  desc = 'mep.nvim: like :MepAiSendSelection, but prompts for an extra instruction first',
})

vim.api.nvim_create_user_command('MepAiAgent', function(cmd_opts)
  local scope = cmd_opts.range > 0 and { cmd_opts.line1, cmd_opts.line2 } or nil
  require('mep.ai.agent').start({ scope = scope })
end, {
  range = true,
  desc = 'mep.nvim: start the mep.ai tool-calling agent, opening its panel (usable as :\'<,\'>MepAiAgent to scope it to a range)',
})

vim.api.nvim_create_user_command('MepAiAgentPrompt', function(cmd_opts)
  local scope = cmd_opts.range > 0 and { cmd_opts.line1, cmd_opts.line2 } or nil
  require('mep.ai.popup').prompt('mep.ai: instructions', function(instructions)
    require('mep.ai.agent').start({ scope = scope, instructions = instructions })
  end)
end, {
  range = true,
  desc = 'mep.nvim: like :MepAiAgent, but prompts for an extra instruction first',
})

vim.api.nvim_create_user_command('MepAiCancel', function()
  local ai = require('mep.ai')
  local agent = require('mep.ai.agent')
  if ai.is_streaming() then
    ai.cancel()
  elseif agent.is_busy() then
    agent.cancel()
  else
    vim.notify('mep.ai: nothing in flight', vim.log.levels.INFO)
  end
end, { desc = 'mep.nvim: cancel an in-flight mep.ai request (a plain stream or the current agent turn)' })

vim.api.nvim_create_user_command('MepAiSetKey', function(cmd_opts)
  require('mep.ai').set_key(cmd_opts.args ~= '' and cmd_opts.args or nil)
end, {
  nargs = '?',
  complete = function()
    return vim.tbl_keys(require('mep.ai').config.options.providers)
  end,
  desc = 'mep.nvim: prompt for and cache an API key for a mep.ai provider (default: the configured one)',
})

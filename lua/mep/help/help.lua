--- Aggregator for mep's help system: a searchable `mep.picker` index of
--- every curated library's one-line description, every visible Ex
--- command, and every visible keymap (`mep.help.index`). `<CR>` either
--- opens the matching `:help` tag, runs the command, or executes the
--- keymap exactly as if pressed — `mep.picker.sources.commands.run`/
--- `mep.whichkey.whichkey.execute` reused for the latter two rather
--- than reimplementing "run this thing" a third time.
local config = require('mep.help.config')
local index = require('mep.help.index')
local commands_mod = require('mep.picker.sources.commands')
local whichkey_mod = require('mep.whichkey')

local M = {}

--- Run `item` (`mep.help.index.build`'s own shape): open its `:help`
--- tag, run its command, or execute its keymap.
function M.run(item)
  if item.kind == 'doc' then
    local ok = pcall(vim.cmd, 'help ' .. item.tag)
    if not ok then
      vim.notify(
        'mep.help: no :help tag "' .. item.tag .. '" (run :helptags on mep.nvim\'s own doc/ directory first)',
        vim.log.levels.WARN
      )
    end
  elseif item.kind == 'command' then
    commands_mod.run(item.cmd)
  elseif item.kind == 'keymap' then
    whichkey_mod.execute(item.m)
  end
end

--- Open the help picker over the current buffer's commands/keymaps plus
--- every curated library description.
function M.picker()
  require('mep.picker').start({
    prompt_title = 'Help',
    items = index.build(vim.api.nvim_get_current_buf()),
    entry_to_string = function(item)
      return item.text
    end,
    on_select = M.run,
  })
end

--- Configure mep.help: extra/override `descriptions` and `keymaps.
--- picker` (global — see mep.help.config.defaults). Works with sensible
--- defaults even if this is never called.
function M.setup(opts)
  local options = config.setup(opts)
  for _, lhs in ipairs(options.keymaps.picker) do
    vim.keymap.set('n', lhs, M.picker, { desc = 'mep.help: search commands/keymaps/docs' })
  end
  return options
end

return M

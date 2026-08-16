--- Builds the combined command + keymap + library-description item list
--- `mep.help.help`'s picker searches: three existing sources reused
--- wholesale rather than a separate index this library would have to
--- keep in sync itself — `mep.picker.sources.commands` for Ex commands,
--- `mep.whichkey.registry` for real keymap introspection, `mep.help.
--- descriptions` for the curated library list.
local commands_mod = require('mep.picker.sources.commands')
local registry = require('mep.whichkey.registry')
local descriptions = require('mep.help.descriptions')
local config = require('mep.help.config')

local M = {}

--- Every library-description item: `{ kind = 'doc', text, tag }`, one
--- per `mep.help.descriptions.registry` entry merged with `config.
--- options.descriptions` (extra/override), sorted by library name.
local function doc_items()
  local merged = vim.tbl_deep_extend('force', descriptions.registry, config.options.descriptions)
  local names = vim.tbl_keys(merged)
  table.sort(names)
  local items = {}
  for _, name in ipairs(names) do
    local entry = merged[name]
    items[#items + 1] = { kind = 'doc', text = string.format(':help %s — %s', entry.tag, entry.desc), tag = entry.tag }
  end
  return items
end

--- Every command item: `{ kind = 'command', text, cmd }`, `mep.picker.
--- sources.commands.collect`/`.display`'s own shape.
local function command_items(bufnr)
  local items = {}
  for _, cmd in ipairs(commands_mod.collect(bufnr)) do
    items[#items + 1] = { kind = 'command', text = commands_mod.display(cmd), cmd = cmd }
  end
  return items
end

--- Every normal-mode keymap item (buffer-local and global, `mep.
--- whichkey.registry.all`'s own resolution order — real Neovim
--- built-ins aren't included, since `nvim_get_keymap`/`nvim_buf_get_
--- keymap` only ever report user-defined mappings): `{ kind = 'keymap',
--- text, m }`.
local function keymap_items(bufnr)
  local items = {}
  for _, m in ipairs(registry.all('n', bufnr)) do
    local lhs = vim.fn.keytrans(m.lhsraw)
    items[#items + 1] = { kind = 'keymap', text = string.format('%s — %s', lhs, registry.label(m)), m = m }
  end
  return items
end

--- The full picker item list for `bufnr`: every curated library
--- description, every visible Ex command, every visible normal-mode
--- keymap.
function M.build(bufnr)
  local items = {}
  vim.list_extend(items, doc_items())
  vim.list_extend(items, command_items(bufnr))
  vim.list_extend(items, keymap_items(bufnr))
  return items
end

return M

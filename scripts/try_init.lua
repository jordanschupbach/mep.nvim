-- Standalone config for `just try`: loads mep.nvim straight from this repo
-- checkout (found relative to this file, so it works regardless of cwd),
-- with default setup() and the keymaps suggested in the README. Meant to
-- be run with `nvim --clean -u scripts/try_init.lua`, isolated from any
-- real user config.

local this_file = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(this_file, ':p:h:h')

vim.opt.runtimepath:prepend(root)
vim.cmd('runtime! plugin/mep.lua')

-- Deliberately no `cd` here: the session should operate on whatever
-- directory the user launched from. `just try` already runs from the repo
-- root, and under `nix run` this file lives in the read-only Nix store —
-- cd-ing to `root` there would strand the session in /nix/store.

vim.o.termguicolors = true
vim.o.number = true
vim.o.cursorline = true

-- mep.sanity's default config sets <leader> to space; nothing else here
-- needs to touch mapleader for the <leader>ff/fg/fb maps below to work.
-- treesitter's ensure_installed defaults to true, which would otherwise
-- kick off cloning/compiling the whole curated parser list on every
-- `just try` launch — fine for real use, too heavy for a quick scratch
-- session, so this opts out; highlighting still activates normally for
-- whatever parsers are already available.
require('mep').setup({
  treesitter = { ensure_installed = false },
  picker = { triggers = { buffer_search = { '/' } } },
})

vim.keymap.set('n', '<leader>ff', '<cmd>MepFileTreeToggle<cr>', { desc = 'mep: toggle file tree' })
vim.keymap.set('n', '<leader>pf', '<cmd>MepFindFiles<cr>', { desc = 'mep: find files' })
vim.keymap.set('n', '<leader>bb', '<cmd>MepBuffers<cr>', { desc = 'mep: open buffers' })
vim.keymap.set('n', '<leader>bs', '<cmd>MepScratch<cr>', { desc = 'mep: open scratch buffer' })
vim.keymap.set('n', '<leader>fg', '<cmd>MepLiveGrep<cr>', { desc = 'mep: live grep' })
vim.keymap.set('n', '<leader>fb', '<cmd>MepBufferSearch<cr>', { desc = 'mep: buffer search' })
vim.keymap.set('n', '<leader>po', '<cmd>MepProjects<cr>', { desc = 'mep: switch projects' })

-- Deliberately no startup vim.notify() and no `:edit` of a starting file
-- here: a multi-line notify at VimEnter exceeds the default cmdheight (1)
-- and triggers Neovim's "Press ENTER or type command to continue"
-- hit-enter prompt on every launch, and opening a file replaces Neovim's
-- normal empty-buffer intro screen. Leaving the initial buffer untouched
-- gives the standard `nvim` startup experience; see README.md for the
-- "Suggested keymaps" section if you forget one.

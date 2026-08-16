--- Curated one-line description + vimdoc tag per library — the exact
--- text after the em dash in each library's own `README.md` `### `mep.
--- <name>`` heading, paired with the `*mep-<name>*` tag `doc/mep.txt`
--- gives that same section (see that file's own CONTENTS block). Kept
--- in README order.
local M = {}

M.registry = {
  core = { desc = 'async/parallel building blocks', tag = 'mep-core' },
  sanity = { desc = 'sane Neovim defaults', tag = 'mep-sanity' },
  dashboard = { desc = "a startup dashboard, in place of Neovim's own intro", tag = 'mep-dashboard' },
  scratch = { desc = 'a single, persistent throwaway notepad buffer', tag = 'mep-scratch' },
  icons = { desc = 'file/directory icons, no special font required', tag = 'mep-icons' },
  filetree = { desc = 'a file tree sidebar, using mep.icons', tag = 'mep-filetree' },
  symbols = { desc = 'an LSP-backed symbols outline', tag = 'mep-symbols' },
  hints = { desc = 'jump-to-location hints, hop.nvim/flash.nvim-style', tag = 'mep-hints' },
  dap = { desc = 'a native Debug Adapter Protocol client', tag = 'mep-dap' },
  docs = { desc = 'docstring generation and external doc lookup', tag = 'mep-docs' },
  flashcards = { desc = 'spaced-repetition review, org-drill style', tag = 'mep-flashcards' },
  picker = { desc = 'search and pick, with a preview sidebar', tag = 'mep-picker' },
  project = { desc = 'a small, persisted list of project directories, with a picker', tag = 'mep-project' },
  treesitter = { desc = 'activates treesitter, installs common parsers', tag = 'mep-treesitter' },
  org = { desc = 'org-mode structure and highlighting', tag = 'mep-org' },
  markdown = { desc = 'visual styling for markdown buffers', tag = 'mep-markdown' },
  whichkey = { desc = 'a popup showing what is bound under a prefix key', tag = 'mep-whichkey' },
  sidebar = { desc = 'build your own side (or top/bottom) panel', tag = 'mep-sidebar' },
  notify = { desc = 'nvim-notify/noice-style toast popups, plus a dismissible history panel', tag = 'mep-notify' },
  activitybar = { desc = 'a notifications/todo/tests/git button bar, built on mep.sidebar', tag = 'mep-activitybar' },
  lsp = { desc = 'LSP client setup, no lspconfig/mason needed', tag = 'mep-lsp' },
  completion = { desc = 'a generic, pluggable completion engine', tag = 'mep-completion' },
  url = { desc = 'find and open URLs in any buffer', tag = 'mep-url' },
  git = { desc = 'gutter signs, hunk actions, and a status panel', tag = 'mep-git' },
  window = { desc = 'a tiling-window-manager-style layer over Neovim splits', tag = 'mep-window' },
  theme = { desc = 'a curated colorscheme collection, with a fuzzy picker', tag = 'mep-theme' },
  chrome = {
    desc = 'statusline/winbar/tabline/statuscolumn widgets, and an active-window border',
    tag = 'mep-chrome',
  },
  ai = { desc = 'gptel-style LLM streaming and a tool-calling agent, in any buffer', tag = 'mep-ai' },
}

return M

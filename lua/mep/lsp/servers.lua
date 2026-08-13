--- Curated registry of common LSP servers, shaped as `vim.lsp.Config`
--- tables (`cmd`/`filetypes`/`root_markers` — see `:help vim.lsp.Config`)
--- ready to hand to `vim.lsp.config(name, cfg)`. Enough to cover most
--- everyday editing without trying to be nvim-lspconfig's own much
--- larger catalogue — the same "curated slice, not the whole registry"
--- tradeoff `mep.treesitter.parsers` already makes for grammars, and
--- deliberately covering the same languages where it makes sense (lua,
--- python, js/ts, go, rust, c/cpp, bash, json, yaml, markdown).
---
--- None of these are auto-installed (unlike `mep.treesitter`'s parsers,
--- which are — a C compiler + `git clone` is a uniform install path
--- across every grammar; a language server's install path is wildly
--- heterogeneous — npm, pip, go install, cargo, curl+prebuilt binary —
--- with no single zero-dependency mechanism that covers all of them).
--- `mep.lsp` only ever *activates* a server whose `cmd[1]` is already
--- found on `PATH` (`vim.fn.executable`) — install it yourself however
--- your package manager of choice wants to.
local M = {}

M.registry = {
  lua_ls = {
    cmd = { 'lua-language-server' },
    filetypes = { 'lua' },
    root_markers = { { '.luarc.json', '.luarc.jsonc' }, '.git' },
  },
  pyright = {
    cmd = { 'pyright-langserver', '--stdio' },
    filetypes = { 'python' },
    root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', 'pyrightconfig.json', '.git' },
  },
  ts_ls = {
    cmd = { 'typescript-language-server', '--stdio' },
    filetypes = { 'javascript', 'javascriptreact', 'javascript.jsx', 'typescript', 'typescriptreact', 'typescript.tsx' },
    root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' },
  },
  gopls = {
    cmd = { 'gopls' },
    filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
    root_markers = { 'go.work', 'go.mod', '.git' },
  },
  rust_analyzer = {
    cmd = { 'rust-analyzer' },
    filetypes = { 'rust' },
    root_markers = { 'Cargo.toml', '.git' },
  },
  clangd = {
    cmd = { 'clangd' },
    filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
    root_markers = { '.clangd', 'compile_commands.json', 'compile_flags.txt', '.git' },
  },
  bashls = {
    cmd = { 'bash-language-server', 'start' },
    filetypes = { 'sh', 'bash' },
    root_markers = { '.git' },
  },
  jsonls = {
    cmd = { 'vscode-json-language-server', '--stdio' },
    filetypes = { 'json', 'jsonc' },
    root_markers = { '.git' },
  },
  yamlls = {
    cmd = { 'yaml-language-server', '--stdio' },
    filetypes = { 'yaml', 'yaml.docker-compose' },
    root_markers = { '.git' },
  },
  marksman = {
    cmd = { 'marksman', 'server' },
    filetypes = { 'markdown', 'markdown.mdx' },
    root_markers = { '.marksman.toml', '.git' },
  },
}

--- Names of every server in the curated registry, sorted.
function M.names()
  local names = {}
  for name in pairs(M.registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M

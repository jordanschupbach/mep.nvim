--- Curated registry of common LSP servers, shaped as `vim.lsp.Config`
--- tables (`cmd`/`filetypes`/`root_markers` — see `:help vim.lsp.Config`)
--- ready to hand to `vim.lsp.config(name, cfg)`. Enough to cover most
--- everyday editing without trying to be nvim-lspconfig's own much
--- larger catalogue — the same "curated slice, not the whole registry"
--- tradeoff `mep.treesitter.parsers` already makes for grammars, and
--- deliberately covering the same languages where it makes sense (lua,
--- python, js/ts, go, rust, c/cpp, bash, json, yaml, markdown, zig, nim,
--- crystal, java, kotlin, haskell, ocaml, d, ruby, elixir, julia,
--- clojure, perl, r, php, csharp, fortran, scala) — the same set
--- `mep.org.babel` executes, wherever a real LSP for one exists at all
--- (see that module's own header comment on the "LSP + tree-sitter
--- grammar, then babel" policy this repo's language support follows).
---
--- Every `cmd`/`filetypes`/`root_markers` triple below is adapted from
--- (usually copied straight out of) nvim-lspconfig's own `lsp/<name>.lua`
--- default config for that server — confirmed against a real install of
--- each rather than guessed. Two real capabilities this registry's plain
--- static-table shape can't reproduce, both simplified away the same
--- direction every other entry here already simplifies: a `root_dir`
--- that's a *function* (elixir-ls's own "prefer the outer of two
--- `mix.exs` files, for an umbrella app" logic; csharp-ls's own
--- fallback chain across `*.sln`/`*.slnx`/`*.csproj` globs) collapses to
--- a flat `root_markers` list (nearest match only, no glob support —
--- same "no fixed glob-able filename, `.git` alone" tradeoff
--- `haskell_language_server`/`ocamllsp`/`nimlsp` already document); a
--- `cmd` that's a *function* (csharp-ls's own wrapper, setting the
--- spawned process' cwd to the resolved root dir, since csharp-ls
--- discovers its own project file relative to cwd rather than an
--- argument) collapses to a plain `cmd` table, so `csharp_ls` below may
--- not find its project file when Neovim's own cwd differs from the
--- buffer's project root.
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
  zls = {
    cmd = { 'zls' },
    filetypes = { 'zig' },
    root_markers = { 'build.zig', '.git' },
  },
  nimlsp = {
    cmd = { 'nimlsp' },
    filetypes = { 'nim' },
    -- No fixed nimble-manifest filename to list (it's named after the
    -- project, e.g. `foo.nimble`) — `.git` alone, same fallback bashls/
    -- jsonls/yamlls already use for the same reason.
    root_markers = { '.git' },
  },
  crystalline = {
    cmd = { 'crystalline' },
    filetypes = { 'crystal' },
    root_markers = { 'shard.yml', '.git' },
  },
  -- No `-data <workspace>` argument (real jdtls configs, e.g. nvim-
  -- jdtls, usually generate one per-project) — `mep.lsp`'s own `cmd`
  -- tables are static, no per-root dynamic argument injection anywhere
  -- in this registry; confirmed empirically that a bare `jdtls` still
  -- starts and serves requests without one, just reusing its own
  -- default shared workspace across every Java project instead of a
  -- dedicated one per project (Eclipse's own index cache, not a
  -- correctness problem — worse cross-project cache reuse, nothing
  -- more).
  jdtls = {
    cmd = { 'jdtls' },
    filetypes = { 'java' },
    root_markers = { 'pom.xml', 'build.gradle', 'build.gradle.kts', '.git' },
  },
  kotlin_language_server = {
    cmd = { 'kotlin-language-server' },
    filetypes = { 'kotlin' },
    root_markers = { 'settings.gradle', 'settings.gradle.kts', 'pom.xml', '.git' },
  },
  -- `--lsp` (not a bare invocation): `haskell-language-server-wrapper`
  -- also doubles as a CLI diagnostic tool (`--version`, `--probe-tools`,
  -- ...) — this flag is what actually puts it into LSP stdio mode. The
  -- wrapper itself picks whichever `haskell-language-server-<ghc
  -- version>` binary matches the project's own GHC, rather than this
  -- registry needing to know that version itself.
  -- No fixed `*.cabal` filename to list (it's named after the package,
  -- e.g. `foo.cabal`, and `root_markers` here are always literal names,
  -- never globs — same reasoning `nimlsp`'s own entry above documents
  -- for `*.nimble`) — the fixed project-level files real Haskell
  -- tooling also looks for, then `.git`.
  haskell_language_server = {
    cmd = { 'haskell-language-server-wrapper', '--lsp' },
    filetypes = { 'haskell' },
    root_markers = { 'stack.yaml', 'cabal.project', 'package.yaml', '.git' },
  },
  -- Same "no fixed glob-able filename" reasoning as `haskell_language_
  -- server` above for `*.opam` — `dune-project` (or `.git`) instead.
  ocamllsp = {
    cmd = { 'ocamllsp' },
    filetypes = { 'ocaml' },
    root_markers = { 'dune-project', '.git' },
  },
  -- `handlers['window/showMessageRequest']` overrides serve-d's own
  -- built-in DCD version check (`doGlobalStartup` in its own `extension.
  -- d`, confirmed against its source) — it unconditionally compares
  -- whatever `dcd-client`/`dcd-server` it finds (or doesn't find at all)
  -- against a version number hardcoded into that specific serve-d
  -- release, and interrupts with a real `showMessageRequest` popup
  -- ("DCD is outdated...", offering to download/compile a new one) the
  -- moment its client starts — every session, completely independent of
  -- `d.enableAutoComplete`/`d.aggressiveUpdate` (neither gates this
  -- specific startup check, only what happens *after* the user answers
  -- it). There's no actual server-side setting that skips it. On a
  -- Nix-managed machine specifically this is worse than a one-off
  -- annoyance: `dcd-client`/`dcd-server` (if present at all) come from
  -- the Nix store, read-only and version-pinned by the flake, not
  -- something serve-d's own auto-updater could ever actually replace —
  -- so every single answer to that prompt is wrong for this setup, not
  -- just inconvenient. Silently declining leaves DCD-backed completion
  -- off for the session, same as manually clicking "Continue anyway"
  -- would — every other component (dscanner diagnostics, dfmt
  -- formatting, hover, ...) still works. Any other `showMessageRequest`
  -- this client sends still goes to Neovim's own default handler,
  -- unaffected.
  --
  -- Returns `vim.NIL`, not bare Lua `nil` — this handler's return value
  -- becomes the literal JSON-RPC *response* sent back to the server (a
  -- client-side `handlers` entry is dispatched directly, unlike the
  -- global `vim.lsp.handlers` table, which Neovim's own runtime wraps
  -- with boilerplate that tolerates a bare `nil`). Confirmed empirically:
  -- returning plain `nil` throws `method "window/showMessageRequest":
  -- either a result or an error must be sent to the server in response`
  -- from `vim.lsp.rpc`'s own dispatcher, since a Lua `nil` result is
  -- indistinguishable there from "no response at all" — `vim.NIL` is
  -- Neovim's own sentinel for a real, present JSON `null`, which is what
  -- "user dismissed the dialog, chose nothing" actually serializes to
  -- over LSP.
  serve_d = {
    cmd = { 'serve-d' },
    filetypes = { 'd' },
    root_markers = { 'dub.json', 'dub.sdl', '.git' },
    handlers = {
      ['window/showMessageRequest'] = function(err, result, ctx, config)
        if result and result.message and result.message:find('DCD is outdated', 1, true) then
          return vim.NIL
        end
        return vim.lsp.handlers['window/showMessageRequest'](err, result, ctx, config)
      end,
    },
  },
  ruby_lsp = {
    cmd = { 'ruby-lsp' },
    filetypes = { 'ruby' },
    root_markers = { 'Gemfile', '.git' },
  },
  -- Real elixir-ls ships with no `cmd` set at all (nvim-lspconfig
  -- deliberately leaves the absolute path to the user's own unzipped
  -- install) — the nixpkgs-packaged binary is just called `elixir-ls`,
  -- so unlike upstream's own config this can default to that directly.
  elixirls = {
    cmd = { 'elixir-ls' },
    filetypes = { 'elixir', 'eelixir' },
    root_markers = { 'mix.exs', '.git' },
  },
  -- LanguageServer.jl/SymbolServer.jl/StaticLint.jl are installed via
  -- Julia's own `Pkg`, not nixpkgs (no standalone `julials`-style binary
  -- exists to package) — `cmd` is nvim-lspconfig's own `julials` script
  -- verbatim, which loads those three packages from
  -- `~/.julia/environments/nvim-lspconfig` (falling back to the regular
  -- load path if that environment doesn't exist), the install location
  -- `julia --project=~/.julia/environments/nvim-lspconfig -e 'using
  -- Pkg; Pkg.add("LanguageServer"); Pkg.add("SymbolServer");
  -- Pkg.add("StaticLint")'` sets up. Same "install it yourself, `cmd[1]`
  -- (`julia`) just needs to already be on PATH" contract every other
  -- entry here already has.
  julials = {
    cmd = {
      'julia',
      '--startup-file=no',
      '--history-file=no',
      '-e',
      [[
        ls_install_path = joinpath(
            get(DEPOT_PATH, 1, joinpath(homedir(), ".julia")),
            "environments", "nvim-lspconfig"
        )
        pushfirst!(LOAD_PATH, ls_install_path)
        using LanguageServer, SymbolServer, StaticLint
        popfirst!(LOAD_PATH)
        depot_path = get(ENV, "JULIA_DEPOT_PATH", "")
        project_path = let
            dirname(something(
                Base.load_path_expand((
                    p = get(ENV, "JULIA_PROJECT", nothing);
                    p === nothing ? nothing : isempty(p) ? nothing : p
                )),
                Base.current_project(),
                get(Base.load_path(), 1, nothing),
                Base.load_path_expand("@v#.#"),
            ))
        end
        server = LanguageServer.LanguageServerInstance(stdin, stdout, project_path, depot_path)
        server.runlinter = true
        run(server)
      ]],
    },
    filetypes = { 'julia' },
    root_markers = { 'Project.toml', 'JuliaProject.toml', '.git' },
  },
  clojure_lsp = {
    cmd = { 'clojure-lsp' },
    filetypes = { 'clojure' },
    root_markers = { 'project.clj', 'deps.edn', 'build.boot', 'shadow-cljs.edn', 'bb.edn', '.git' },
  },
  -- Confirmed empirically: a bare `perlnavigator` invocation immediately
  -- errors ("Connection input stream is not set") without an explicit
  -- transport flag — `--stdio` is what `mep.lsp` (stdio-only, like every
  -- server here) needs.
  perlnavigator = {
    cmd = { 'perlnavigator', '--stdio' },
    filetypes = { 'perl' },
    root_markers = { '.git' },
  },
  -- `languageserver` is an R package (CRAN), not a standalone binary —
  -- `-e 'languageserver::run()'` is real nvim-lspconfig's own
  -- `r_language_server` launch convention. Same "install it yourself"
  -- contract as every other entry here (`cmd[1]` is `R`, already needed
  -- for `mep.org.babel`'s own `r` language def's `Rscript` sibling
  -- anyway).
  r_language_server = {
    cmd = { 'R', '--no-echo', '-e', 'languageserver::run()' },
    filetypes = { 'r' },
    root_markers = { '.git' },
  },
  phpactor = {
    cmd = { 'phpactor', 'language-server' },
    filetypes = { 'php' },
    root_markers = { 'composer.json', '.phpactor.json', '.phpactor.yml', '.git' },
  },
  -- See this file's own header comment on why `root_markers` is just
  -- `.git` (real csharp-ls discovers its own `*.sln`/`*.slnx`/`*.csproj`
  -- via cwd-relative globbing, neither of which this registry's flat
  -- literal-name `root_markers` can express) and why `cmd` may not find
  -- a project file when Neovim's cwd differs from the buffer's project
  -- root (real csharp-ls also needs its spawning process' cwd set to
  -- the root dir, which this registry's plain `cmd` table has no hook
  -- for).
  csharp_ls = {
    cmd = { 'csharp-ls' },
    filetypes = { 'cs' },
    root_markers = { '.git' },
  },
  fortls = {
    cmd = { 'fortls', '--notify_init', '--hover_signature', '--hover_language=fortran', '--use_signature_help' },
    filetypes = { 'fortran' },
    root_markers = { '.fortls', '.git' },
  },
  metals = {
    cmd = { 'metals' },
    filetypes = { 'scala' },
    root_markers = { 'build.sbt', 'build.sc', 'build.gradle', 'pom.xml', '.git' },
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

{
  description = "mep.nvim - a zero-dependency Neovim plugin/distribution";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.systems.url = "github:nix-systems/default";
  inputs.flake-utils = {
    url = "github:numtide/flake-utils";
    inputs.systems.follows = "systems";
  };

  outputs =
    { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # `nix run` entry point: the same "try" experience as `just try`,
        # a scratch Neovim with this checkout loaded via setup({}),
        # isolated from any real user config. See scripts/try_init.lua.
        #
        # try_init.lua locates the plugin root relative to its own path
        # (two directories up), so it must be referenced via `self` (the
        # whole flake source tree in the store) rather than copied in on
        # its own, which would lose the surrounding directory structure.
        mep-try = pkgs.writeShellApplication {
          name = "mep-try";
          runtimeInputs = [
            pkgs.neovim
            pkgs.ripgrep
          ];
          text = ''
            exec nvim --clean -u ${self}/scripts/try_init.lua "$@"
          '';
        };

        # Prebuilt tree-sitter grammars (parser .so + that same grammar's
        # own `queries/` dir) for the devShell, laid out as `nvim/site/
        # {parser,queries}/...` so setting `$XDG_DATA_DIRS` to this
        # derivation's own store path (see the devShell's `shellHook`
        # below) puts it on Neovim's default 'runtimepath' for free —
        # confirmed empirically (`XDG_DATA_DIRS=/some/dir nvim --headless
        # -c 'lua print(vim.o.runtimepath)'`) that Neovim appends
        # `<dir>/nvim/site` for every `:`-separated entry, no wrapper or
        # init.lua change needed. An experiment: mep.treesitter's own
        # `git clone` + compile install (git/gcc both already in this
        # shell) should already produce the same result at runtime, so if
        # syntax highlighting still doesn't show up with these prebuilt
        # *and* pre-available, the install step itself isn't the
        # remaining variable.
        #
        # name (matching `lua/mep/treesitter/parsers.lua`'s own registry
        # keys, so a real install there never conflicts with this) -> the
        # nixpkgs `tree-sitter-grammars` package providing it. Every
        # entry here pairs a grammar with *that same package's own*
        # queries, never mep's own hand-written ones — mep ships no
        # hand-written queries for any language except `org` (the only
        # directory under this repo's own `queries/`), so there's no risk
        # of a query file going stale against a different upstream's node
        # types the way there would be mixing grammars.
        #
        # Deliberately excludes three of `parsers.lua`'s own entries:
        #  - `org`: nixpkgs' `tree-sitter-org-nvim` builds a *different*,
        #    incompatible grammar (milisims/tree-sitter-org) from the one
        #    `queries/org/*.scm` (this repo's own, hand-written) is
        #    written against (nvim-orgmode/tree-sitter-org) — swapping it
        #    in would break org's own base highlighting, not just fail to
        #    add anything. Left to mep.treesitter's own install, which
        #    already fetches the right one.
        #  - `php`/`php_only`: nixpkgs' prebuilt php grammar ships no
        #    `queries/` directory at all, and has no `php_only` variant
        #    (the one `mep.org.polyglot` actually needs for embedded
        #    org-babel PHP blocks — see `lua/mep/org/lang.lua`'s own
        #    comment on why) — left to mep.treesitter's own install too.
        #  - `vimdoc`: not in nixpkgs' `tree-sitter-grammars` set at all.
        #  - `ocaml`: same as php — nixpkgs' prebuilt grammar ships no
        #    `queries/` directory at all — left to mep.treesitter's own
        #    install.
        #  - `nim`/`d`: not in nixpkgs' `tree-sitter-grammars` set at all
        #    (confirmed empirically: no `tree-sitter-nim`/`tree-sitter-d`
        #    attribute exists) — both are in `parsers.lua`'s own curated
        #    registry, so mep.treesitter's own git-clone-and-compile
        #    install still covers them, same as php/ocaml above, just
        #    without even a parser head start from this derivation.
        # `perl`/`typescript`/`tsx` are included below despite nixpkgs'
        # prebuilt grammar for each shipping *no* `queries/` directory
        # either (confirmed empirically, same as php/ocaml) — unlike those
        # two, still worth listing here: `perl.so`/`typescript.so`/`tsx.so`
        # landing on runtimepath at all still saves mep.treesitter's own
        # install a full git-clone-and-compile the first time an org
        # buffer with one of these embedded needs it, leaving only a
        # (much cheaper, no compiler needed) git-clone-for-queries-only
        # step at that point — see `mep.treesitter.install.M.install`'s
        # own `parser_ready` branch. That queries step still needs a
        # network connection at runtime, same as php/ocaml/nim/d always
        # have; there's no nix-only way to get real highlighting for any
        # of these five. `perl` itself has no entry in `parsers.lua` at
        # all yet (added alongside this comment) — `r` still doesn't, and
        # stays a parser-only, no-highlights case for now, same tradeoff
        # `queries/org/injections.scm`'s own header comment already
        # documents for both.
        mep-treesitter-grammars =
          let
            # Not in `grammars` below along with everything else: nixpkgs'
            # tree-sitter-crystal ships a real `queries/` directory, but
            # its actual highlights.scm (and folds/context/aerial) live
            # nested under `queries/nvim/` instead — the top-level
            # `queries/` only has `injections.scm` — a real, if unusual,
            # upstream layout (confirmed empirically), not a nixpkgs
            # packaging quirk, so the generic per-grammar loop below
            # (which only ever looks at `<grammar>/queries` directly)
            # would silently install injections with no highlights at all.
            # Handled as its own copy step, sourcing `queries/nvim/`
            # instead, right after that loop.
            crystalGrammar = pkgs.tree-sitter-grammars.tree-sitter-crystal;
            grammars = {
              bash = pkgs.tree-sitter-grammars.tree-sitter-bash;
              c = pkgs.tree-sitter-grammars.tree-sitter-c;
              clojure = pkgs.tree-sitter-grammars.tree-sitter-clojure;
              cpp = pkgs.tree-sitter-grammars.tree-sitter-cpp;
              c_sharp = pkgs.tree-sitter-grammars.tree-sitter-c-sharp;
              css = pkgs.tree-sitter-grammars.tree-sitter-css;
              dockerfile = pkgs.tree-sitter-grammars.tree-sitter-dockerfile;
              elixir = pkgs.tree-sitter-grammars.tree-sitter-elixir;
              fortran = pkgs.tree-sitter-grammars.tree-sitter-fortran;
              go = pkgs.tree-sitter-grammars.tree-sitter-go;
              haskell = pkgs.tree-sitter-grammars.tree-sitter-haskell;
              html = pkgs.tree-sitter-grammars.tree-sitter-html;
              java = pkgs.tree-sitter-grammars.tree-sitter-java;
              javascript = pkgs.tree-sitter-grammars.tree-sitter-javascript;
              json = pkgs.tree-sitter-grammars.tree-sitter-json;
              julia = pkgs.tree-sitter-grammars.tree-sitter-julia;
              kotlin = pkgs.tree-sitter-grammars.tree-sitter-kotlin;
              lua = pkgs.tree-sitter-grammars.tree-sitter-lua;
              markdown = pkgs.tree-sitter-grammars.tree-sitter-markdown;
              markdown_inline = pkgs.tree-sitter-grammars.tree-sitter-markdown-inline;
              perl = pkgs.tree-sitter-grammars.tree-sitter-perl;
              python = pkgs.tree-sitter-grammars.tree-sitter-python;
              query = pkgs.tree-sitter-grammars.tree-sitter-query;
              r = pkgs.tree-sitter-grammars.tree-sitter-r;
              ruby = pkgs.tree-sitter-grammars.tree-sitter-ruby;
              rust = pkgs.tree-sitter-grammars.tree-sitter-rust;
              scala = pkgs.tree-sitter-grammars.tree-sitter-scala;
              sql = pkgs.tree-sitter-grammars.tree-sitter-sql;
              toml = pkgs.tree-sitter-grammars.tree-sitter-toml;
              tsx = pkgs.tree-sitter-grammars.tree-sitter-tsx;
              typescript = pkgs.tree-sitter-grammars.tree-sitter-typescript;
              vim = pkgs.tree-sitter-grammars.tree-sitter-vim;
              yaml = pkgs.tree-sitter-grammars.tree-sitter-yaml;
              zig = pkgs.tree-sitter-grammars.tree-sitter-zig;
            };
          in
          pkgs.runCommand "mep-treesitter-grammars" { } (
            ''
              mkdir -p $out/nvim/site/parser $out/nvim/site/queries
            ''
            + pkgs.lib.concatStrings (
              pkgs.lib.mapAttrsToList (name: grammar: ''
                install -Dm444 ${grammar}/parser $out/nvim/site/parser/${name}.so
                if [ -d ${grammar}/queries ]; then
                  mkdir -p $out/nvim/site/queries/${name}
                  cp -r ${grammar}/queries/. $out/nvim/site/queries/${name}/
                fi
              '') grammars
            )
            + ''
              install -Dm444 ${crystalGrammar}/parser $out/nvim/site/parser/crystal.so
              mkdir -p $out/nvim/site/queries/crystal
              cp -r ${crystalGrammar}/queries/nvim/. $out/nvim/site/queries/crystal/
            ''
            + ''
              # tree-sitter-cpp's own highlights.scm is a thin C++-only
              # overlay (class/template/namespace/...) that assumes it's
              # layered over `c`'s own query via a `; inherits: c`
              # modeline — real for nvim-treesitter's own curated cpp
              # query, but the raw upstream repo's highlights.scm (what
              # this derivation copies, same as mep.treesitter's own
              # runtime install does) doesn't declare it. Without this
              # line cpp gets zero captures for anything c's own rules
              # would normally cover (primitive_type, identifier, ...) —
              # confirmed empirically building mep.treesitter's own
              # install path (see lua/mep/treesitter/install.lua's own
              # `INHERITS` table, the same fix, applied there at runtime
              # instead of here at build time).
              sed -i '1i ;; inherits: c' $out/nvim/site/queries/cpp/highlights.scm
            ''
          );
      in
      {
        packages.default = mep-try;

        apps.default = flake-utils.lib.mkApp { drv = mep-try; };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.neovim
            pkgs.ripgrep
            pkgs.just
            pkgs.luajitPackages.busted
            pkgs.luajitPackages.nlua

            # git + a C compiler: mep.treesitter's own install pipeline
            # (`git clone` + compile) for its curated parser registry —
            # both mep.org's own `org` parser and, since mep.org.polyglot
            # (see README's "Poly mode"), whichever *embedded* languages'
            # parsers a given org file's src blocks actually use
            # (`mep.org.polyglot.ensure_language_parsers`). Not needed by
            # the plugin itself to *run* — see the note below this list —
            # only to build parsers on a machine (like NixOS) with nothing
            # on PATH by default.
            pkgs.git
            pkgs.gcc

            # mep.ai's own HTTP client — a real `curl` subprocess (see
            # lua/mep/ai/job.lua's own header comment for why: no HTTP
            # client Lua dependency, same "external tool via a job, not a
            # runtime Lua dep" contract as git/gcc above). Usually already
            # on PATH on most systems, but not guaranteed on NixOS
            # specifically, same reasoning as everything else in this
            # list.
            pkgs.curl
            # A local LLM to develop/try mep.ai against without any
            # account or API key — see this repo's own README ("mep.ai")
            # for the two-terminal `ollama serve` + `ollama pull llama3.2`
            # flow this pairs with (`mep.ai.config`'s own `ollama` preset
            # already points at its default `localhost:11434`).
            pkgs.ollama

            # Interpreters/compilers for org/test.org's mep.org.babel
            # examples (see lua/mep/org/babel.lua's `M.languages`) — not
            # needed by the plugin itself (which stays a zero-runtime-
            # dependency, editor-only tool per this repo's own
            # conventions), just for manually trying each babel language
            # out in a scratch Neovim.
            pkgs.python3 # Python
            pkgs.nodejs # JavaScript
            pkgs.ruby
            pkgs.perl
            # `languageserver` bundled in, not bare `pkgs.R` — gives
            # `r_language_server` (below) something to `library()` into,
            # on top of the same `R`/`Rscript` binaries `M.languages.r`
            # itself already needs.
            (pkgs.rWrapper.override { packages = [ pkgs.rPackages.languageserver ]; })
            pkgs.php
            pkgs.rustc # Rust
            pkgs.cargo # rust-analyzer needs this too, not just rustc — it
            # shells out to `cargo metadata` for its own workspace
            # discovery; without it a .rs file loads with no Cargo.toml-
            # based project info at all ("Failed to discover workspace"),
            # confirmed empirically to mean zero LSP features, not a
            # merely degraded single-file mode.
            pkgs.go
            pkgs.bun # TypeScript, via `bun <file>` directly
            pkgs.beamPackages.elixir
            pkgs.julia-bin
            pkgs.babashka # Clojure, `bb` — tried before the full `clojure`
            # CLI below (much faster startup; see `M.languages.clojure`'s
            # own comment on why both are listed)
            pkgs.clojure
            pkgs.gfortran
            # .NET 10, not the default `pkgs.dotnet-sdk` (.NET 8 as of this
            # writing) — `M.languages.csharp`'s own `dotnet run <file>.cs`
            # "file-based apps" mode (no `.csproj` needed) only exists
            # starting .NET 10.
            pkgs.dotnet-sdk_10
            pkgs.scala

            # Zig, Nim, Crystal, Java — `zig run`/`nim r`/`crystal run`
            # each compile and run a file in one step (no separate
            # compile+run split `M.languages.zig`/`.nim`/`.crystal` need
            # to manage); Java is a real two-step `javac`+`java` (see
            # `M.languages.java`'s own comment on why `binary_path` gets
            # reused as a directory of `.class` files there).
            pkgs.zig
            pkgs.nim
            pkgs.crystal
            pkgs.jdk

            # Kotlin, Haskell, OCaml, D — `kotlin <file>.kts`/`runghc
            # <file>.hs`/`ocaml <file>.ml` each run a script directly,
            # same one-command shape as zig/nim/crystal above; D is a
            # real two-step `dmd` compile-then-run (see `M.languages.d`'s
            # own comment on why its own `compile_cmd` differs from gcc/
            # g++/rustc's shared `-o <path>` shape).
            pkgs.kotlin
            pkgs.ghc
            pkgs.ocaml
            # Built with gcc14Stdenv, not the default gcc15: upstream dmd's
            # own C header importer (used to build phobos's zlib bindings)
            # can't parse gcc 15's system headers, which now use the C23
            # `nullptr` keyword (stddef.h) — a real nixpkgs-unstable/dmd
            # incompatibility, not anything specific to this flake. Drop
            # this override once nixpkgs' dmd derivation itself accounts
            # for gcc 15 headers.
            (pkgs.dmd.override { stdenv = pkgs.gcc14Stdenv; })

            # LSP servers matching mep.lsp.servers' own curated registry
            # (lua/mep/lsp/servers.lua) — again, purely for trying
            # mep.lsp/mep.org.polyglot out in *this* dev shell. mep.lsp
            # only ever activates a server whose `cmd[1]` is already on
            # PATH (`vim.fn.executable`); it never installs one itself,
            # by design (see mep.lsp.servers' own header comment: unlike
            # tree-sitter grammars, there's no single install mechanism
            # that covers npm/pip/cargo/go-install/prebuilt-binary
            # uniformly). On NixOS specifically — where nothing lands on
            # PATH globally by default — that means *some* project-local
            # shell (this one, or your own) has to list them; mep.nvim
            # itself stays free of any hard runtime dependency either
            # way, editor-only, same as every other library in this repo.
            pkgs.lua-language-server
            pkgs.pyright
            pkgs.typescript-language-server
            pkgs.gopls
            pkgs.rust-analyzer
            pkgs.clang-tools # clangd
            pkgs.bash-language-server
            pkgs.vscode-langservers-extracted # vscode-json-language-server
            pkgs.yaml-language-server
            pkgs.marksman
            pkgs.zls
            pkgs.nimlsp
            pkgs.crystalline
            pkgs.jdt-language-server
            pkgs.kotlin-language-server
            pkgs.haskell-language-server
            pkgs.ocamlPackages.ocaml-lsp
            pkgs.serve-d
            pkgs.ruby-lsp
            pkgs.elixir-ls
            # No LSP entry here for Julia: LanguageServer.jl/SymbolServer.jl/
            # StaticLint.jl install via Julia's own `Pkg`, not nixpkgs (see
            # `mep.lsp.servers`' own `julials` entry) — nothing this flake
            # could add to PATH would make that install step unnecessary.
            pkgs.clojure-lsp
            pkgs.perlnavigator
            pkgs.phpactor
            pkgs.csharp-ls
            pkgs.fortls
            pkgs.metals
          ];

          # Puts `mep-treesitter-grammars` (above) on Neovim's default
          # 'runtimepath' for any `nvim` run from this shell — see that
          # derivation's own header comment for why `$XDG_DATA_DIRS` is
          # the mechanism (Neovim appends `<dir>/nvim/site` per `:`-
          # separated entry to its own default rtp, no wrapper or config
          # change needed) and what it deliberately does/doesn't cover.
          # Confirmed empirically that `stdpath('data')/site` — where
          # mep.treesitter's own runtime install writes — is always
          # earlier in Neovim's default rtp than anything `$XDG_DATA_DIRS`
          # contributes, ahead of *or* behind an existing value here; a
          # real install, once one succeeds, is found first either way,
          # this is only ever a fallback for whatever it hasn't provided.
          shellHook = ''
            export XDG_DATA_DIRS="${mep-treesitter-grammars}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
          '';
        };
      }
    );
}

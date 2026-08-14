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

            # Interpreters/compilers for org/test.org's mep.org.babel
            # examples (see lua/mep/org/babel.lua's `M.languages`) — not
            # needed by the plugin itself (which stays a zero-runtime-
            # dependency, editor-only tool per this repo's own
            # conventions), just for manually trying each babel language
            # out in a scratch Neovim.
            pkgs.gcc # C, C++
            pkgs.python3 # Python
            pkgs.nodejs # JavaScript
            pkgs.ruby
            pkgs.perl
            pkgs.R
            pkgs.php
            pkgs.rustc # Rust
            pkgs.go
          ];
        };
      }
    );
}

# SPDX-FileCopyrightText: 2026 Farid Zakaria
# SPDX-License-Identifier: MIT
{
  description = "GuixPkgs: Guix packages via Nix";

  nixConfig = {
    extra-substituters = [ "https://guixpkgs.cachix.org" ];
    extra-trusted-public-keys = [
      "guixpkgs.cachix.org-1:rM4xwCs5NUy+FcCKkiWP/CmRaSVxxDPaKWZvM1bRopg="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guix-src = {
      url = "git+https://codeberg.org/guix/guix.git?ref=version-1.5.0&shallow=1";
      flake = false;
    };
    guix-transfer.url = "github:fzakaria/guix-transfer";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      guix-src,
      guix-transfer,
      treefmt-nix,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      # treefmt: one formatter front-end for the whole repo.
      #   nix    -> nixfmt
      #   bash   -> shfmt
      #   python -> black
      #   toml   -> taplo
      #   scheme -> `guix style -f` (whole-file reindent; works on any .scm,
      #             not just package definitions, and needs no guix-daemon).
      # The vendored/generated Guix trees are never touched.
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";

        settings.global.excludes = [
          "pkgs/store/**"
          "pkgs/sources/**"
          "flake.lock"
        ];

        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        programs.black.enable = true;
        programs.taplo.enable = true;

        settings.formatter.scheme = {
          command = "${pkgs.guix}/bin/guix";
          options = [
            "style"
            "-f"
          ];
          includes = [ "*.scm" ];
        };
      };

      # Lazily load all by-name packages. Each by-name file imports its translated
      # derivation from pkgs/store directly; the store files reference each other
      # by `(import ../store/<file>.nix).<output>`, so the whole graph resolves
      # without any extra machinery. Package-specific build fixups are applied at
      # translation time in guix-transfer (see README "Patching packages"), so
      # there is deliberately no overlay layer here.
      readByName =
        dir:
        let
          letters = builtins.readDir dir;
          loadLetter =
            letter: type:
            if type == "directory" then
              lib.mapAttrs' (
                fn: _: lib.nameValuePair (lib.removeSuffix ".nix" fn) (import (dir + "/${letter}/${fn}"))
              ) (lib.filterAttrs (n: _: lib.hasSuffix ".nix" n) (builtins.readDir (dir + "/${letter}")))
            else
              { };
        in
        lib.foldl' (a: b: a // b) { } (lib.mapAttrsToList loadLetter letters);

      # The sync logic lives in sync.py (a fully typed Python module); the two
      # build-time values it needs are substituted into its placeholder constants.
      sync-script =
        pkgs.writers.writePython3Bin "sync-guix"
          {
            flakeIgnore = [ "E501" ]; # long /nix/store paths and the channel fingerprint
          }
          (
            builtins.replaceStrings
              [ "@guixCommit@" "@guixTransfer@" ]
              [
                guix-src.rev
                "${guix-transfer.packages.${system}.default}/bin/guix-transfer"
              ]
              (builtins.readFile ./sync.py)
          );

    in
    {
      packages.${system} =
        (if builtins.pathExists ./pkgs/by-name then readByName ./pkgs/by-name else { })
        // {
          # The sync tool itself, exposed so it can be built (`nix build .#sync-guix`)
          # independently of the `nix run .#sync` app.
          sync-guix = sync-script;
        };

      apps.${system}.sync = {
        type = "app";
        program = "${sync-script}/bin/sync-guix";
        meta.description = "Sync the Nix package set from upstream Guix";
      };

      # `nix fmt` formats the tree; `nix flake check` verifies it is formatted.
      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system}.formatting = treefmtEval.config.build.check self;
    };
}

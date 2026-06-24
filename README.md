<p align="center">
  <img src="assets/logo.png" alt="GuixPkgs Logo" width="250" />
</p>

# GuixPkgs

**GuixPkgs** is an ambitious project to bridge the gap between the GNU Guix and Nix ecosystems. It translates the entirety of Guix's package definitions into pure, lazily-evaluable Nix expressions, without relying on Import From Derivation (IFD).

## Motivation

Guix and Nix share the exact same underlying deployment model, but they are built on different languages (Guile Scheme vs. the Nix expression language). While it is technically possible to evaluate Guix packages within Nix using IFD (Import From Derivation), IFD is notoriously slow, breaks evaluation caching, and is forbidden in pure evaluation modes (such as standard Nix flakes).

We want to allow users to transparently mix and match `nixpkgs` and Guix packages within the same Nix flake, retaining fast evaluation and full reproducibility.

## Goal

The goal of this repository is to act as a direct, automated translation layer:
1. Translate all Guix derivations for a given commit into a large, deduplicated set of `.nix` files.
2. Provide a standard Nixpkgs-like interface (`packages.x86_64-linux.<package>`) via a flake, mapping names directly to the translated derivations.
3. Automatically sync and translate the upstream Guix tree on a recurring schedule (e.g. via GitHub Actions), recording the exact Guix state in `guix-metadata.json`.

## How it Works

GuixPkgs leverages [guix-transfer](https://github.com/fzakaria/guix-transfer) to perform a one-time conversion per Guix commit. The resulting repository tree looks like this:

```
guixpkgs/
├── flake.nix             # The entry point exposing the Guix packages as Nix outputs
├── guix-metadata.json    # Tracks the Guix channel, commit, and sync timestamp
├── .github/
│   └── workflows/
│       └── sync.yml      # GitHub Action to periodically sync with upstream Guix
└── pkgs/
    ├── by-name/          # Human-readable entry points mapping to their derivation
    │   ├── h/hello.nix   # e.g., `import ../../store/b6x8v...-hello.drv.nix`
    │   └── z/zile.nix 
    ├── store/            # The deduplicated translated Nix derivations
    │   ├── b6x8v...-hello.drv.nix
    │   ├── a1x9z...-glibc.drv.nix
    │   └── ...
    └── sources/          # Local files (patches, builder scripts) referenced by the derivations
```

## Syncing Manually

You can manually trigger the translation of Guix derivations into Nix expressions at any time. The flake exposes an app to run the synchronization process:

```bash
# Note: This requires `guix` to be installed and the Guix daemon running.
nix run .#sync
```

After the sync completes, make sure to add the newly generated files to your git index so that Nix can evaluate them:

```bash
git add pkgs/
```

## Binary Cache

To avoid building Guix packages from source, you can use the provided Cachix binary cache. You can configure this by adding the following `nixConfig` to your `flake.nix`:

```nix
  nixConfig = {
    extra-substituters = [ "https://guixpkgs.cachix.org" ];
    extra-trusted-public-keys = [ "guixpkgs.cachix.org-1:rM4xwCs5NUy+FcCKkiWP/CmRaSVxxDPaKWZvM1bRopg=" ];
  };
```

Alternatively, you can temporarily use it via the command line:

```bash
nix build .#hello \
  --extra-substituters https://guixpkgs.cachix.org \
  --extra-trusted-public-keys guixpkgs.cachix.org-1:rM4xwCs5NUy+FcCKkiWP/CmRaSVxxDPaKWZvM1bRopg=
```

## Example Usage

Because `GuixPkgs` translates Guix packages into pure Nix expressions, they become standard Nix derivations (technically, they evaluate to an attribute set created by `builtins.derivation { ... }`).

In your own projects, you can mix and match `nixpkgs` and `guixpkgs` seamlessly via flakes:

```nix
{
  description = "A project mixing Nix and Guix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guixpkgs.url = "github:fzakaria/guixpkgs";
  };

  outputs = { self, nixpkgs, guixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    guixPkgs = guixpkgs.packages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.git                   # From Nixpkgs
        guixPkgs.hello             # From Guix (via GuixPkgs)
      ];
    };
  };
}
```

Run standard Nix commands against Guix packages effortlessly:

> [!NOTE]
> Building Guix packages from source within Nix can sometimes fail during bootstrap (e.g., `chmod: Operation not permitted`). This is often because Guix's bootstrap scripts try to restore `SETGID` bits, which the Nix sandbox strictly blocks. To successfully build from source, you may need to disable syscall filtering and/or the sandbox temporarily.

```bash
# Build the GNU Hello package from Guix
nix build .#hello --option filter-syscalls false --option sandbox false

# Drop into a shell with Zile from Guix
nix shell .#zile --option filter-syscalls false --option sandbox false
```

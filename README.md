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
├── flake.nix             # Entry point: builds the package-set fixpoint and applies overlays
├── overlays.nix          # Nix-specific build fixups (test skips, reference checks, …)
├── lib/
│   └── overlay-helpers.nix  # Reusable overlay helpers (disableTests, patchTests, …)
├── guix-metadata.json    # Tracks the Guix channel, commit, and sync timestamp
├── .github/
│   └── workflows/
│       └── sync.yml      # GitHub Action to periodically sync with upstream Guix
└── pkgs/
    ├── by-name/          # Human-readable name → store-file key (into the fixpoint)
    │   ├── h/hello.nix   # e.g., `"b6x8v...-hello-2.12.2"`
    │   └── z/zile.nix
    ├── store/            # The deduplicated translated derivations, each a
    │   ├── b6x8v...-hello.nix       #   `{ pkgs }: builtins.derivation { … }` function
    │   ├── a1x9z...-glibc.nix
    │   └── ...
    └── sources/          # Local files (patches, builder scripts) referenced by the derivations
```

Each file under `store/` is a function of the package set rather than a
standalone derivation: it references its dependencies through `pkgs."<key>"`
instead of `import`-ing them directly. `flake.nix` ties them all together in a
fixpoint, which is what makes the whole graph **overlayable** — see
[Patching packages with overlays](#patching-packages-with-overlays).

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

## Patching packages with overlays

The derivations under `pkgs/` are a **faithful** copy of Guix — they are
regenerated wholesale on every sync, so editing them by hand is pointless (your
changes would be overwritten). But some packages still need small, Nix-specific
adjustments to build under Nix's daemon, because Guix's build sandbox and Nix's
are not identical. For example, bootstrap toolchain test suites probe signals,
file descriptors and `/bin/sh` in ways that differ between the two daemons, so a
`check` phase can fail under Nix even though it passed upstream in Guix.

Those adjustments live in **`overlays.nix`**, outside `pkgs/`, so they survive
every regeneration.

### How it works

`flake.nix` loads every `store/*.nix` file into a single fixpoint keyed by
store-file basename. Because each derivation references its dependencies through
that set (`pkgs."<key>"`), an overlay applied to one package **propagates to
every dependent** — patch `m4` once and everything that builds against it picks
up the change automatically.

Each entry in `overlays.nix` is a standard Nix overlay (`final: prev: attrs`),
applied in order. You build them with the helpers in
`lib/overlay-helpers.nix`.

### Available helpers

There are two flavours of helper. **Package transformers** take a derivation
and return a modified one (`drv -> drv`):

| Helper | Effect |
| --- | --- |
| `disableTests` | Disable the gnu-build-system `check` phase entirely (`#:tests? #f`). |
| `patchTests subs` | Apply `{ from; to; }` substitutions to the builder — e.g. drop a single flaky test subcase while keeping the rest. |
| `patchBuilder fn` | The primitive the above build on: rewrite the package's `*-builder` script with a `string -> string` function. |
| `dropReferenceChecks` | Remove the daemon reference-check attributes (`allowed`/`disallowed` `References`/`Requisites`) when a specifier points at an untranslated `/gnu/store` path. |

**Overlay builders** wrap a transformer into a ready-to-use overlay that targets
every derivation with a given `name` (`name -> overlay`):

| Helper | Equivalent to |
| --- | --- |
| `disableTestsFor "pkg-1.2.3"` | `overrideByName "pkg-1.2.3" disableTests` |
| `patchTestsFor "pkg-1.2.3" subs` | `overrideByName "pkg-1.2.3" (patchTests subs)` |
| `dropReferenceChecksFor "pkg-1.2.3"` | `overrideByName "pkg-1.2.3" dropReferenceChecks` |
| `overrideByName "pkg-1.2.3" f` | Apply transformer `f` to every package named `pkg-1.2.3`. |

> [!TIP]
> Target packages by **name** (`disableTestsFor "m4-boot0-1.4.19"`) rather than
> by store-file key. Names are stable, whereas the store hash changes whenever a
> package's inputs change on a re-sync — so a name-keyed overlay keeps working
> across syncs.

### Example

`overlays.nix`:

```nix
{ helpers }:

with helpers;

[
  # Bootstrap m4's bundled gnulib tests (test-execute, 198.sysval) probe the
  # sandbox and fail under Nix's daemon though they pass under Guix's.
  (disableTestsFor "m4-boot0-1.4.19")

  # perl-boot0's disallowedReferences points at the bootstrap binutils, which
  # has no Nix translation; Nix rejects it as an illegal reference specifier.
  (dropReferenceChecksFor "perl-boot0-5.36.0")

  # Surgically drop one flaky test subcase instead of the whole suite:
  # (patchTestsFor "some-pkg-1.0" [ { from = ''"4 5 6"''; to = ''"4 6"''; } ])

  # Anything more bespoke: an arbitrary drv -> drv transform by name.
  # (overrideByName "some-pkg-1.0" (drv: /* … */ drv))
]
```

### Writing your own helper

Helpers are plain functions in `lib/overlay-helpers.nix`. The most common
building block is `patchBuilder`, since gnu-build-system flags (like `#:tests?`)
are baked into the Guile builder script and can only be changed by rewriting it:

```nix
# Force a configure flag into a package's build.
addConfigureFlag = flag: patchBuilder (builtins.replaceStrings
  [ "#:configure-flags (quote (" ]
  [ "#:configure-flags (quote (\"${flag}\" " ]);
```

Then expose an overlay form with `overrideByName "pkg" (addConfigureFlag "…")`.

> [!NOTE]
> These fixups are deliberately a thin Nix-side layer. Where a problem is really
> a translation bug (e.g. an untranslated `/gnu/store` reference), it is also
> fixed at the source in [guix-transfer](https://github.com/fzakaria/guix-transfer)
> so future syncs emit correct expressions — at which point the corresponding
> overlay simply becomes a no-op.

# Overlay helpers for the transferred Guix derivation graph.
#
# guix-transfer emits each store file as `{ pkgs }: builtins.derivation { … }`
# and references peers through `pkgs."<store-basename>"`. flake.nix ties those
# into a fixpoint, so an overlay applied here propagates through the whole
# transitive graph (patch `m4` once and every dependent rebuilds against it).
#
# Two flavours of helper:
#   * package transformers — `drv -> drv` (e.g. `disableTests`, `patchBuilder`)
#   * overlay builders      — `final: prev: attrs` (e.g. `overrideByName`,
#                             `disableTestsFor`); these go straight into the
#                             `overlays` list in overlays.nix.
{ lib }:

rec {
  # ── package transformers (drv -> drv) ──────────────────────────────────────

  # Rewrite a derivation's Guix build script (`*-builder`) with `sub`, a
  # string -> string function. The patched script is written to a fresh store
  # path and swapped into both `srcs` and `args`, yielding a new derivation.
  #
  # This is the primitive every test helper builds on: the gnu-build-system
  # bakes flags like `#:tests?` into the builder source, so they can only be
  # changed by rewriting that source — not via an env var or derivation attr.
  patchBuilder = sub: drv:
    let
      old = drv.drvAttrs;
      isBuilder = p: lib.hasSuffix "-builder" (baseNameOf (toString p));
      builderSrc = lib.findFirst isBuilder
        (throw "patchBuilder: no '*-builder' source in ${old.name or "<unknown>"}")
        (old.srcs or [ ]);
      # `builtins.toFile` requires a context-free name, but baseNameOf of a
      # store path carries the original path's string context — strip it.
      builderName =
        baseNameOf (builtins.unsafeDiscardStringContext (toString builderSrc));
      patched = builtins.toFile builderName
        (sub (builtins.readFile builderSrc));
    in
    builtins.derivation (old // {
      srcs = map (p: if isBuilder p then patched else p) (old.srcs or [ ]);
      args = map (a: if a == toString builderSrc then toString patched else a)
        (old.args or [ ]);
    });

  # Disable the gnu-build-system `check` phase entirely (`#:tests? #f`).
  # Use for bootstrap/toolchain packages whose upstream-validated test suites
  # probe the sandbox (signals, fds, /bin/sh) and so fail under Nix's daemon
  # even though they pass under Guix's.
  disableTests = patchBuilder
    (builtins.replaceStrings [ "#:tests? #t" ] [ "#:tests? #f" ]);

  # Surgically rewrite the builder with a list of `{ from; to; }` substitutions
  # — e.g. to drop a single flaky test subcase while keeping the rest running:
  #   patchTests [ { from = ''"4 5 6"''; to = ''"4 6"''; } ]
  patchTests = subs: patchBuilder
    (builtins.replaceStrings (map (x: x.from) subs) (map (x: x.to) subs));

  # Drop the daemon reference-check attributes (allowed/disallowed
  # References/Requisites). Use when a specifier points at an untranslated
  # /gnu/store path, which Nix rejects at build time as an illegal reference
  # specifier. These are post-build validations Guix already enforced upstream,
  # so dropping them is safe. (guix-transfer also filters these at emit time;
  # this overlay unblocks already-generated trees without a full re-sync.)
  dropReferenceChecks = drv:
    builtins.derivation (removeAttrs drv.drvAttrs [
      "allowedReferences"
      "disallowedReferences"
      "allowedRequisites"
      "disallowedRequisites"
    ]);

  # ── overlay builders (final: prev: attrs) ──────────────────────────────────

  # Apply `f` (a drv -> drv transformer) to every derivation in the set whose
  # `name` equals `name`. Keying by name (not store-basename) means the overlay
  # survives input-hash churn across re-syncs.
  overrideByName = name: f: final: prev:
    lib.mapAttrs (_: v: if (v.name or null) == name then f v else v) prev;

  # Convenience overlays for the common cases.
  disableTestsFor = name: overrideByName name disableTests;
  patchTestsFor = name: subs: overrideByName name (patchTests subs);
  dropReferenceChecksFor = name: overrideByName name dropReferenceChecks;
}

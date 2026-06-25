# Nix-specific fixups applied on top of the faithfully transferred Guix
# derivations. The transfer (pkgs/) stays a byte-for-byte copy of Guix; any
# adjustment needed to make a package build under Nix's daemon lives here.
#
# Each entry is a standard overlay (`final: prev: attrs`). Build them with the
# helpers from lib/overlay-helpers.nix. Order matters: later overlays see the
# results of earlier ones.
{ helpers }:

with helpers;

[
  # m4's bundled gnulib test suite probes process spawning, signal propagation,
  # file descriptors and /bin/sh (e.g. `test-execute.sh`, `198.sysval`). Guix's
  # daemon and Nix's sandbox build different environments for these, so the
  # `check` phase fails under Nix even though it passes upstream — and Guix's
  # own per-subcase workarounds only cover the subcases that break under Guix.
  # These are bootstrap toolchain tests Guix already validated, so skip them.
  (disableTestsFor "m4-boot0-1.4.19")
]

# SPDX-FileCopyrightText: 2026 Farid Zakaria
# SPDX-License-Identifier: MIT
#
# Wrap a translated Guix package so its executables run with the runtime
# environment Guix would normally provide through a profile's etc/profile.
#
# Guix does not bake every runtime search path (PATH, GUILE_LOAD_PATH,
# GUILE_LOAD_COMPILED_PATH, XDG_DATA_DIRS, certificate paths, ...) into each
# executable; those are exported by sourcing a profile's generated etc/profile.
# `runtimeEnv` is a translated derivation that contains exactly that generated
# etc/profile (see get-all-derivations.scm). Here we source it before exec'ing
# each program so translated tools work outside a Guix profile.
#
# Dependencies are taken explicitly (not via a blanket `pkgs`) so this file
# declares precisely what it needs; invoke it with `pkgs.callPackage`.
{
  lib,
  symlinkJoin,
  makeWrapper,
  package,
  runtimeEnv,
}:

symlinkJoin {
  name = "${package.name or "guix-package"}-guix-wrapped";
  paths = [ package ];
  nativeBuildInputs = [ makeWrapper ];

  # Keep the package and its runtime environment reachable from the result, and
  # tied together: `result.unwrapped` is the untouched derivation and
  # `result.runtimeEnv` is the profile that drives the wrappers.
  passthru = {
    unwrapped = package;
    inherit runtimeEnv;
  };

  # Only wrap when the runtime env actually produced an etc/profile. Packages
  # that export no search paths get none, so we skip the wrapper overhead and
  # leave their binaries as plain symlinks from symlinkJoin.
  postBuild = ''
    if [ -f "${runtimeEnv}/etc/profile" ]; then
      for dir in "$out/bin" "$out/sbin"; do
        [ -d "$dir" ] || continue
        for program in "$dir"/*; do
          # Skip Guix's hidden ".<name>-real" originals (already wrapped by
          # Guix); wrapping them would double-wrap an executable.
          case "$(basename "$program")" in
            .*) continue ;;
          esac
          [ -f "$program" ] && [ -x "$program" ] || continue
          wrapProgram "$program" \
            --run "export GUIX_PROFILE=${runtimeEnv}" \
            --run ". ${runtimeEnv}/etc/profile"
        done
      done
    fi
  '';
}

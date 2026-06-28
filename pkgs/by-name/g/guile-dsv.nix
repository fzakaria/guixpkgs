{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/v59vv01602slqf0rq6vb5xknh9k31y3f-guile-dsv-0.8.0.nix;
  runtimeEnv = import ../../store/wkld4gg09baapnji2qn38wvdp8vxxaqr-guile-dsv-runtime-env.nix;
}

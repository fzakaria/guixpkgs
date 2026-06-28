{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/nya4p04x9qvnx1rbxyaczmsxj83n200d-guile-wisp-1.0.12.nix;
  runtimeEnv = import ../../store/bdjjzy7a8yc1l7q28wn3frhh77svlsyp-guile-wisp-runtime-env.nix;
}

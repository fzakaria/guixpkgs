{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/r1shrfphadbpqqrp2wjijvqmsw0kxww7-guile-cv-0.4.0.nix;
  runtimeEnv = import ../../store/6a3jwz7r6vpnx2jjqbx6sn2bf4qzbkml-guile-cv-runtime-env.nix;
}

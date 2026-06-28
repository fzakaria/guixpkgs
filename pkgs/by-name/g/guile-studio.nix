{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/zkakjvfsgzfx432k8ps7b57saa5hzxzd-guile-studio-0.1.1-1.dd0ad42.nix;
  runtimeEnv = import ../../store/pwc04blj5nckcfm3vz4ak9rxgn2c9r59-guile-studio-runtime-env.nix;
}

{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/71831kwfic918x9b89ixws2191v7gfzk-coreutils-9.1.nix;
  runtimeEnv = import ../../store/ngh47phcpr4iblqvmwxrrsl298x1gw3z-coreutils-runtime-env.nix;
}

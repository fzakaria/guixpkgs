{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/qhf6a0wbc81xv6zy6v9fmlik5xch8m4h-guile-pipe-0.0.0-0.0746ec3.nix;
  runtimeEnv = import ../../store/xcxl19rbiwyp38mml3cq9cxb5aqcxbpj-guile-pipe-runtime-env.nix;
}

{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/xv7wf6a3zhn5z4jgnbcc4c9bhqrzwgji-hello-2.12.2.nix;
  runtimeEnv = import ../../store/9gfggknhm3d4h3632n9316k5s1lzdx95-hello-runtime-env.nix;
}

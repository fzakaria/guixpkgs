{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/vjbik9wkyyjssw2vkix7c2znc7d16yjc-guile-png-0.8.0.nix;
  runtimeEnv = import ../../store/y7pk50bypi7j9y4ybqkibjbccl0f6dyx-guile-png-runtime-env.nix;
}

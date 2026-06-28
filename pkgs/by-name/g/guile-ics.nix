{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/a33aha5hrx0jbrw0g869fxj5igq2k4rl-guile-ics-0.7.0.nix;
  runtimeEnv = import ../../store/x3l4syivh6cjvk7hijaj078alq7j2318-guile-ics-runtime-env.nix;
}

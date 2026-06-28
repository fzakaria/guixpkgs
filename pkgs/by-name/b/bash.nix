{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/6gznwawm88kxfavwyklghwhx8hrif0qm-bash-5.2.37.nix;
  runtimeEnv = import ../../store/ffd06ph8x0zmiy2w9q7q59q0j9hk9hjr-bash-runtime-env.nix;
}

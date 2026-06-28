{ pkgs }:
pkgs.callPackage ../../wrap-guix-package.nix {
  package = import ../../store/ab86d1m9h945mmfh204g2f1ndl5ncsx1-g-golf-0.8.2.nix;
  runtimeEnv = import ../../store/jaxknlhp2kcyvykh6mwgw0lhkj9ksa09-g-golf-runtime-env.nix;
}

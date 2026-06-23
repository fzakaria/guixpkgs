{
  description = "GuixPkgs: Guix packages via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guix-src = {
      url = "git+https://git.savannah.gnu.org/git/guix.git?ref=version-1.5.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Helper to lazily load all by-name packages
    readDir = builtins.readDir;
    readByName = dir:
      let
        letters = readDir dir;
        loadLetter = letter: type:
          if type == "directory" then
            let
              pkgFiles = readDir (dir + "/${letter}");
              loadPkg = name: type:
                if type == "regular" && pkgs.lib.hasSuffix ".nix" name then
                  { name = pkgs.lib.removeSuffix ".nix" name; value = import (dir + "/${letter}/${name}"); }
                else null;
            in
              builtins.listToAttrs (builtins.filter (x: x != null) (pkgs.lib.mapAttrsToList loadPkg pkgFiles))
          else {};
      in
        builtins.foldl' (a: b: a // b) {} (pkgs.lib.mapAttrsToList loadLetter letters);

  in {
    packages.${system} = readByName ./pkgs/by-name;
  };
}

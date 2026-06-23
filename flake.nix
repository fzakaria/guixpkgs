{
  description = "GuixPkgs: Guix packages via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guix-src = {
      url = "git+https://git.savannah.gnu.org/git/guix.git?ref=version-1.5.0&shallow=1";
      flake = false;
    };
    guix-transfer.url = "github:fzakaria/guix-transfer";
  };

  outputs = { self, nixpkgs, guix-src, guix-transfer }: 
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

    sync-script = pkgs.writeShellScriptBin "sync-guix" ''
      set -euo pipefail

      echo "Fetching derivations..."
      cat > channels.scm <<EOF
      (list (channel
              (name 'guix)
              (url "https://git.savannah.gnu.org/git/guix.git")
              (commit "${guix-src.rev}")
              (introduction
               (make-channel-introduction
                "9edb3f66fd807b096b48283debdcddccfea34bad"
                (openpgp-fingerprint
                 "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
      EOF

      # Use guix time-machine to perfectly decouple from the host's daemon version
      guix time-machine -C channels.scm -- repl ./get-all-derivations.scm > drv_mapping.txt
      
      echo "Translating Guix derivations to Nix expressions..."
      awk '{print $2}' drv_mapping.txt | xargs ${guix-transfer.packages.${system}.default}/bin/guix-transfer > transfer_out.txt

      echo "Creating by-name mapping..."
      mkdir -p pkgs/by-name
      rm -rf pkgs/by-name/*
      
      awk '/^\/nix\/store/ {print $1}' transfer_out.txt > nix_drvs.txt

      while read -r name drv_path; do
          if grep -q "^$drv_path$" nix_drvs.txt; then
              letter=$(echo "$name" | cut -c 1 | tr '[:upper:]' '[:lower:]')
              mkdir -p "pkgs/by-name/$letter"
              
              nix_filename=$(basename "$drv_path" | sed 's/\.drv$/.nix/')
              echo "import ../../store/$nix_filename" > "pkgs/by-name/$letter/$name.nix"
          fi
      done < drv_mapping.txt
      
      echo "Writing metadata..."
      echo "{ \"channel\": \"guix\", \"commit\": \"${guix-src.rev}\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\" }" > guix-metadata.json
      
      echo "Cleaning up..."
      rm channels.scm drv_mapping.txt transfer_out.txt nix_drvs.txt
      
      echo "Done!"
    '';

  in {
    packages.${system} = readByName ./pkgs/by-name;
    
    apps.${system}.sync = {
      type = "app";
      program = "${sync-script}/bin/sync-guix";
    };
  };
}

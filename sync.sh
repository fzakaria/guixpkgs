#!/usr/bin/env bash
set -euo pipefail

GUIX_TRANSFER_BIN="/home/fmzakari/code/github.com/fzakaria/guix-transfer/target/release/guix-transfer"
if [ ! -f "$GUIX_TRANSFER_BIN" ]; then
    echo "Please build guix-transfer first: cargo build --release in ../guix-transfer"
    exit 1
fi

echo "Fetching derivations..."
# NixOS rule: Use nix-shell -p steam-run -- steam-run if we need to run foreign bins, but guix repl works natively with guix
guix repl get-target-derivations.scm > drv_mapping.txt

DRVS=$(awk '{print $2}' drv_mapping.txt)

echo "Translating to Nix..."
rm -rf pkgs/
mkdir -p pkgs/by-name
$GUIX_TRANSFER_BIN --emit-nix-dir ./pkgs $DRVS

echo "Creating by-name mapping..."
while read -r name drv; do
    DRV_BASE=$(basename "$drv")
    
    first_letter=${name:0:1}
    mkdir -p "pkgs/by-name/$first_letter"
    
    echo "import ../../store/${DRV_BASE}.nix" > "pkgs/by-name/$first_letter/$name.nix"
done < drv_mapping.txt

echo "Writing metadata..."
echo "{ \"channel\": \"guix\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\" }" > guix-metadata.json

echo "Done!"

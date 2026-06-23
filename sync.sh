#!/usr/bin/env bash
set -euo pipefail

GUIX_TRANSFER_BIN="/home/fmzakari/code/github.com/fzakaria/guix-transfer/target/release/guix-transfer"
if [ ! -f "$GUIX_TRANSFER_BIN" ]; then
    echo "Please build guix-transfer first: cargo build --release in ../guix-transfer"
    exit 1
fi

echo "Fetching derivations..."
# Use guix time-machine to perfectly decouple from the host's daemon version
guix time-machine -C channels.scm -- repl get-all-derivations.scm > drv_mapping.txt

DRVS=$(awk '{print $2}' drv_mapping.txt)

echo "Translating to Nix..."
rm -rf pkgs/
mkdir -p pkgs/by-name
$GUIX_TRANSFER_BIN --emit-nix-dir ./pkgs $DRVS > transfer_out.txt

echo "Creating by-name mapping..."
# Extract just the /nix/store paths
grep "^/nix/store/" transfer_out.txt > nix_drvs.txt

# Combine package name from drv_mapping.txt with the final Nix path from nix_drvs.txt
paste <(awk '{print $1}' drv_mapping.txt) nix_drvs.txt | while read -r name nix_drv; do
    NIX_BASE=$(basename "$nix_drv" .drv).nix
    
    first_letter=${name:0:1}
    mkdir -p "pkgs/by-name/$first_letter"
    
    echo "import ../../store/${NIX_BASE}" > "pkgs/by-name/$first_letter/$name.nix"
done

echo "Writing metadata..."
echo "{ \"channel\": \"guix\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\" }" > guix-metadata.json

echo "Done!"

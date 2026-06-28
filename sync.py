# SPDX-FileCopyrightText: 2026 Farid Zakaria
# SPDX-License-Identifier: MIT
"""Sync the Nix package set from upstream Guix.

Pipeline:
  1. Resolve each requested package's derivation with ``guix time-machine``.
  2. Translate those Guix derivations to Nix with ``guix-transfer``.
  3. Lay the results out under ``pkgs/by-name/<letter>/<name>.nix``.
  4. Record provenance in ``guix-metadata.json``.

The two ``@...@`` constants below are substituted by ``flake.nix`` at build
time; running this module outside the flake leaves them as literal placeholders.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

# Injected by Nix at build time (see flake.nix).
GUIX_COMMIT: str = "@guixCommit@"
GUIX_TRANSFER: str = "@guixTransfer@"

REPO = Path.cwd()
PKGS = REPO / "pkgs"
STORE = PKGS / "store"
BY_NAME = PKGS / "by-name"
DERIVATIONS_SCRIPT = REPO / "get-all-derivations.scm"
METADATA_FILE = REPO / "guix-metadata.json"


@dataclass(frozen=True)
class GuixChannel:
    """A Guix channel pin, rendered into a ``channels.scm`` for time-machine."""

    name: str
    url: str
    commit: str
    introduction_commit: str
    introduction_fingerprint: str

    def to_scheme(self) -> str:
        return f"""(list (channel
        (name '{self.name})
        (url "{self.url}")
        (commit "{self.commit}")
        (introduction
         (make-channel-introduction
          "{self.introduction_commit}"
          (openpgp-fingerprint
           "{self.introduction_fingerprint}")))))
"""


@dataclass(frozen=True)
class GuixDerivation:
    """One row of ``get-all-derivations.scm`` output: name + store .drv path."""

    name: str
    drv_path: str

    @classmethod
    def parse(cls, line: str) -> "GuixDerivation":
        name, drv_path = line.split("\t")
        return cls(name=name, drv_path=drv_path)


@dataclass(frozen=True)
class TransferredPackage:
    """A Guix package translated to a Nix derivation in ``pkgs/store``."""

    name: str
    nix_drv_path: str

    @property
    def store_filename(self) -> str:
        """The ``.nix`` file expected under ``pkgs/store`` for this package."""
        return Path(self.nix_drv_path).with_suffix(".nix").name

    @property
    def letter(self) -> str:
        return self.name[0].lower()


@dataclass(frozen=True)
class GuixMetadata:
    """Provenance written to ``guix-metadata.json``."""

    channel: str
    commit: str
    timestamp: str


CHANNEL = GuixChannel(
    name="guix",
    url="https://codeberg.org/guix/guix.git",
    commit=GUIX_COMMIT,
    introduction_commit="9edb3f66fd807b096b48283debdcddccfea34bad",
    introduction_fingerprint="BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA",
)


def run(cmd: list[str]) -> str:
    """Run ``cmd``, let its stderr through, and return its captured stdout."""
    print("+ " + " ".join(cmd), file=sys.stderr)
    completed = subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE)
    return completed.stdout


def fetch_derivations(channels_scm: Path) -> list[GuixDerivation]:
    """Realise every requested package's derivation via ``guix time-machine``."""
    print("Fetching derivations...")
    output = run(
        [
            "guix",
            "time-machine",
            "-C",
            str(channels_scm),
            "--",
            "repl",
            str(DERIVATIONS_SCRIPT),
        ]
    )
    return [GuixDerivation.parse(line) for line in output.splitlines() if line.strip()]


def translate(derivations: list[GuixDerivation]) -> list[TransferredPackage]:
    """Translate Guix derivations to Nix, pairing outputs with inputs by order."""
    print("Translating Guix derivations to Nix expressions...")
    # --disable-tests: skip the gnu-build-system check phase at translation
    # time. Guix's bootstrap test suites probe the daemon sandbox and fail
    # under Nix; this must happen here (not via a Nix overlay) because builders
    # bake in absolute dependency paths -- see README "Patching".
    output = run(
        [
            GUIX_TRANSFER,
            "--disable-tests",
            "--emit-nix-dir",
            "pkgs",
            *(derivation.drv_path for derivation in derivations),
        ]
    )
    # guix-transfer emits one Nix .drv path per input, in order; a blank line
    # marks a derivation it could not translate and is skipped.
    packages: list[TransferredPackage] = []
    for derivation, nix_drv_path in zip(derivations, output.splitlines()):
        nix_drv_path = nix_drv_path.strip()
        if nix_drv_path:
            packages.append(
                TransferredPackage(name=derivation.name, nix_drv_path=nix_drv_path)
            )
    return packages


def write_by_name(packages: list[TransferredPackage]) -> int:
    """Rebuild ``pkgs/by-name`` from translated packages; return count written."""
    print("Creating by-name mapping...")
    if BY_NAME.exists():
        shutil.rmtree(BY_NAME)
    written = 0
    for package in packages:
        if not (STORE / package.store_filename).exists():
            continue
        letter_dir = BY_NAME / package.letter
        letter_dir.mkdir(parents=True, exist_ok=True)
        (letter_dir / f"{package.name}.nix").write_text(
            f"import ../../store/{package.store_filename}\n"
        )
        written += 1
    return written


def write_metadata() -> None:
    """Record the synced channel, commit, and timestamp."""
    print("Writing metadata...")
    metadata = GuixMetadata(
        channel=CHANNEL.name,
        commit=GUIX_COMMIT,
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    METADATA_FILE.write_text(json.dumps(asdict(metadata)) + "\n")


def main() -> None:
    # channels.scm is only needed while time-machine runs, so keep it in a
    # throwaway temp dir instead of polluting the repo.
    with tempfile.TemporaryDirectory() as tmp:
        channels_scm = Path(tmp) / "channels.scm"
        channels_scm.write_text(CHANNEL.to_scheme())
        derivations = fetch_derivations(channels_scm)

    packages = translate(derivations)
    written = write_by_name(packages)
    write_metadata()

    print(f"Done! Wrote {written} packages under {BY_NAME}.")
    print("IMPORTANT: Run 'git add pkgs/' so Nix can see the new files!")


if __name__ == "__main__":
    main()

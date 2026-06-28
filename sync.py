# SPDX-FileCopyrightText: 2026 Farid Zakaria
# SPDX-License-Identifier: MIT
"""Sync the Nix package set from upstream Guix.

Pipeline:
  1. Resolve each package's own derivation plus a generated runtime-environment
     derivation with ``guix time-machine`` (see get-all-derivations.scm).
  2. Translate both derivations to Nix with ``guix-transfer``.
  3. Lay out ``pkgs/by-name/<letter>/<name>.nix`` wrappers that source the
     runtime environment around the translated package.
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
    """One row of ``get-all-derivations.scm`` output.

    Tab-separated: the package name, the package's own ``.drv`` path, and the
    ``.drv`` for its generated runtime-environment profile.
    """

    name: str
    package_drv_path: str
    runtime_env_drv_path: str

    @classmethod
    def parse(cls, line: str) -> "GuixDerivation":
        name, package_drv_path, runtime_env_drv_path = line.split("\t")
        return cls(
            name=name,
            package_drv_path=package_drv_path,
            runtime_env_drv_path=runtime_env_drv_path,
        )


@dataclass(frozen=True)
class TransferredPackage:
    """A translated Guix package paired with its runtime-env derivation."""

    name: str
    package_nix_drv_path: str
    runtime_env_nix_drv_path: str

    @staticmethod
    def _store_filename(nix_drv_path: str) -> str:
        """The ``pkgs/store`` ``.nix`` file name for a translated ``.drv`` path."""
        return Path(nix_drv_path).with_suffix(".nix").name

    @property
    def package_store_filename(self) -> str:
        return self._store_filename(self.package_nix_drv_path)

    @property
    def runtime_env_store_filename(self) -> str:
        return self._store_filename(self.runtime_env_nix_drv_path)

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
    """Translate each package and its runtime-env derivation to Nix.

    The package and runtime-env derivations are fed to guix-transfer interleaved
    (package, env, package, env, ...); it emits one Nix .drv path per input in
    order, so we split the output back into pairs aligned with the inputs.
    """
    print("Translating Guix package and runtime-env derivations to Nix...")
    # --disable-tests: skip the gnu-build-system check phase at translation
    # time. Guix's bootstrap test suites probe the daemon sandbox and fail
    # under Nix; this must happen here (not via a Nix overlay) because builders
    # bake in absolute dependency paths -- see README "Patching".
    drv_paths: list[str] = []
    for derivation in derivations:
        drv_paths.append(derivation.package_drv_path)
        drv_paths.append(derivation.runtime_env_drv_path)
    output = run(
        [GUIX_TRANSFER, "--disable-tests", "--emit-nix-dir", "pkgs", *drv_paths]
    )

    # lines[0::2] are the package drvs, lines[1::2] the matching runtime-env drvs.
    # A blank in either slot marks a derivation guix-transfer skipped.
    lines = output.splitlines()
    packages: list[TransferredPackage] = []
    for derivation, package_nix, env_nix in zip(derivations, lines[0::2], lines[1::2]):
        package_nix, env_nix = package_nix.strip(), env_nix.strip()
        if package_nix and env_nix:
            packages.append(
                TransferredPackage(
                    name=derivation.name,
                    package_nix_drv_path=package_nix,
                    runtime_env_nix_drv_path=env_nix,
                )
            )
    return packages


def by_name_entry(package: TransferredPackage) -> str:
    """Render a by-name entry: a ``{ pkgs }`` function building the wrapper."""
    return (
        "{ pkgs }:\n"
        "pkgs.callPackage ../../wrap-guix-package.nix {\n"
        f"  package = import ../../store/{package.package_store_filename};\n"
        f"  runtimeEnv = import ../../store/{package.runtime_env_store_filename};\n"
        "}\n"
    )


def write_by_name(packages: list[TransferredPackage]) -> int:
    """Rebuild ``pkgs/by-name`` with wrapper entries; return the count written."""
    print("Creating by-name wrappers...")
    if BY_NAME.exists():
        shutil.rmtree(BY_NAME)
    written = 0
    for package in packages:
        package_file = STORE / package.package_store_filename
        runtime_env_file = STORE / package.runtime_env_store_filename
        if not (package_file.exists() and runtime_env_file.exists()):
            continue
        letter_dir = BY_NAME / package.letter
        letter_dir.mkdir(parents=True, exist_ok=True)
        (letter_dir / f"{package.name}.nix").write_text(by_name_entry(package))
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

#!/usr/bin/env python3
"""Check that every native binary in a desktop bundle is for one architecture.

A release bundle is built for x64 or arm64, and everything in it that the
loader opens (the executable, the Flutter engine, the plugins, libwebrtc,
libmpv, CEF) has to be for that architecture: a prebuilt dependency that only
ships x64 would still land in an arm64 bundle, and fail to load on the user's
machine rather than in CI.  This reads the machine field of every PE
(Windows) and ELF (Linux) file in the bundle and fails on the first that does
not match.

    python3 tools/check_bundle_arch.py --bundle rooster/build/linux/arm64/release/bundle --arch arm64
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path
from typing import Iterable, Sequence

PE_MACHINES = {0x8664: "x64", 0xAA64: "arm64", 0x014C: "x86", 0x01C4: "arm"}
ELF_MACHINES = {0x3E: "x64", 0xB7: "arm64", 0x03: "x86", 0x28: "arm"}
ARCHITECTURES = ("x64", "arm64")


def binary_arch(path: Path) -> str | None:
    """The architecture a PE or ELF file was built for, None for other files.

    An unknown machine comes back as ``pe:0x...``/``elf:0x...`` so it still
    fails to match anything.
    """

    with path.open("rb") as stream:
        head = stream.read(64)
        if head[:4] == b"\x7fELF":
            if len(head) < 20:
                return "elf:truncated"
            little_endian = head[5] == 1
            (machine,) = struct.unpack("<H" if little_endian else ">H", head[18:20])
            return ELF_MACHINES.get(machine, f"elf:{machine:#06x}")
        if head[:2] == b"MZ":
            if len(head) < 64:
                return None
            (offset,) = struct.unpack("<I", head[60:64])
            stream.seek(offset)
            signature = stream.read(6)
            if signature[:4] != b"PE\0\0":
                return None
            (machine,) = struct.unpack("<H", signature[4:6])
            return PE_MACHINES.get(machine, f"pe:{machine:#06x}")
    return None


def check_bundle(bundle: Path, arch: str) -> tuple[list[str], list[tuple[str, str]]]:
    """Every native binary under [bundle]: the matching ones, and the rest.

    Returns ``(matching, mismatched)`` as bundle-relative POSIX paths, the
    mismatched ones with the architecture found.
    """

    if arch not in ARCHITECTURES:
        raise ValueError(f"arch must be one of {', '.join(ARCHITECTURES)}")
    if not bundle.is_dir():
        raise ValueError(f"not a directory: {bundle}")
    matching: list[str] = []
    mismatched: list[tuple[str, str]] = []
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        found = binary_arch(path)
        if found is None:
            continue
        relative = path.relative_to(bundle).as_posix()
        if found == arch:
            matching.append(relative)
        else:
            mismatched.append((relative, found))
    return matching, mismatched


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--bundle", required=True, type=Path, help="the built app bundle")
    parser.add_argument("--arch", required=True, choices=ARCHITECTURES, help="what every binary must be")
    args = parser.parse_args(argv)
    try:
        matching, mismatched = check_bundle(args.bundle, args.arch)
    except (OSError, ValueError) as exc:
        print(f"check-bundle-arch: error: {exc}", file=sys.stderr)
        return 2
    for relative, found in mismatched:
        print(f"check-bundle-arch: {relative} is {found}, not {args.arch}", file=sys.stderr)
    if not matching and not mismatched:
        print(f"check-bundle-arch: no native binaries under {args.bundle}", file=sys.stderr)
        return 1
    print(f"check-bundle-arch: {len(matching)} {args.arch} binaries, {len(mismatched)} other")
    return 1 if mismatched else 0


if __name__ == "__main__":
    raise SystemExit(main())

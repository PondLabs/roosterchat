from __future__ import annotations

import struct
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import check_bundle_arch


def _elf(machine: int, little_endian: bool = True) -> bytes:
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2  # 64-bit
    header[5] = 1 if little_endian else 2
    header[18:20] = struct.pack("<H" if little_endian else ">H", machine)
    return bytes(header)


def _pe(machine: int) -> bytes:
    offset = 0x80
    header = bytearray(offset + 24)
    header[:2] = b"MZ"
    header[60:64] = struct.pack("<I", offset)
    header[offset : offset + 4] = b"PE\0\0"
    header[offset + 4 : offset + 6] = struct.pack("<H", machine)
    return bytes(header)


class CheckBundleArchTests(unittest.TestCase):
    def test_reads_pe_and_elf_machines_and_ignores_the_rest(self) -> None:
        with TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "x64.exe").write_bytes(_pe(0x8664))
            (directory / "arm64.dll").write_bytes(_pe(0xAA64))
            (directory / "x64.so").write_bytes(_elf(0x3E))
            (directory / "arm64").write_bytes(_elf(0xB7))
            (directory / "big-endian.so").write_bytes(_elf(0xB7, little_endian=False))
            (directory / "data.json").write_bytes(b'{"not": "a binary"}')
            (directory / "mz-but-not-pe.bin").write_bytes(b"MZ" + bytes(62))
            (directory / "short").write_bytes(b"\x7fELF")
            self.assertEqual(check_bundle_arch.binary_arch(directory / "x64.exe"), "x64")
            self.assertEqual(check_bundle_arch.binary_arch(directory / "arm64.dll"), "arm64")
            self.assertEqual(check_bundle_arch.binary_arch(directory / "x64.so"), "x64")
            self.assertEqual(check_bundle_arch.binary_arch(directory / "arm64"), "arm64")
            self.assertEqual(check_bundle_arch.binary_arch(directory / "big-endian.so"), "arm64")
            self.assertIsNone(check_bundle_arch.binary_arch(directory / "data.json"))
            self.assertIsNone(check_bundle_arch.binary_arch(directory / "mz-but-not-pe.bin"))
            self.assertEqual(check_bundle_arch.binary_arch(directory / "short"), "elf:truncated")

    def test_a_bundle_passes_only_when_every_binary_matches(self) -> None:
        with TemporaryDirectory() as temporary:
            bundle = Path(temporary)
            (bundle / "lib").mkdir()
            (bundle / "rooster").write_bytes(_elf(0xB7))
            (bundle / "lib" / "libflutter_linux_gtk.so").write_bytes(_elf(0xB7))
            (bundle / "data").mkdir()
            (bundle / "data" / "icudtl.dat").write_bytes(b"icu")
            matching, mismatched = check_bundle_arch.check_bundle(bundle, "arm64")
            self.assertEqual(matching, ["lib/libflutter_linux_gtk.so", "rooster"])
            self.assertEqual(mismatched, [])
            self.assertEqual(check_bundle_arch.main(["--bundle", str(bundle), "--arch", "arm64"]), 0)

            # One x64 library (a dependency that only ships x64) fails the bundle.
            (bundle / "lib" / "libmpv.so").write_bytes(_elf(0x3E))
            matching, mismatched = check_bundle_arch.check_bundle(bundle, "arm64")
            self.assertEqual(mismatched, [("lib/libmpv.so", "x64")])
            self.assertEqual(check_bundle_arch.main(["--bundle", str(bundle), "--arch", "arm64"]), 1)
            self.assertEqual(check_bundle_arch.main(["--bundle", str(bundle), "--arch", "x64"]), 1)

    def test_a_bundle_without_binaries_fails(self) -> None:
        with TemporaryDirectory() as temporary:
            bundle = Path(temporary)
            (bundle / "README.md").write_text("nothing native here")
            self.assertEqual(check_bundle_arch.main(["--bundle", str(bundle), "--arch", "x64"]), 1)
            self.assertEqual(
                check_bundle_arch.main(["--bundle", str(bundle / "missing"), "--arch", "x64"]), 2
            )


if __name__ == "__main__":
    unittest.main()

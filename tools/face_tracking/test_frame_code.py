from __future__ import annotations

import unittest

from tools.face_tracking import frame_code


class _Frame:
    """A grey image, enough of one for `draw`: rows of pixels set by slices."""

    def __init__(self, width: int, height: int) -> None:
        self.rows = [[128] * width for _ in range(height)]

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, y: int) -> list[int]:
        return self.rows[y]

    def __setitem__(self, key: tuple[slice, slice], value: int) -> None:
        ys, xs = key
        for row in self.rows[ys]:
            row[xs] = [value] * len(row[xs])

    def luma(self, x: float, y: float) -> float:
        return self.rows[int(y * len(self.rows))][int(x * len(self.rows[0]))]


class FrameCodeTests(unittest.TestCase):
    def test_every_code_is_read_back_at_any_size(self) -> None:
        for width, height in ((640, 480), (320, 180), (101, 67)):
            for code in (0, 1, 2, 57, 185, 4660, 0x8000, 0xFFFF):
                frame = _Frame(width, height)
                frame_code.draw(frame, code)
                self.assertEqual(frame_code.read(frame.luma), code, (width, height, code))

    def test_the_strip_is_the_bottom_sixteenth(self) -> None:
        frame = _Frame(640, 480)
        frame_code.draw(frame, 0xFFFF)
        self.assertEqual(frame.rows[449][0], 128)
        self.assertEqual(frame.rows[450][0], 255)
        self.assertEqual(frame.rows[479][639], 0)

    def test_a_frame_without_a_code_reads_as_none(self) -> None:
        self.assertIsNone(frame_code.read(_Frame(640, 480).luma))

    def test_a_mirrored_frame_reads_as_none(self) -> None:
        frame = _Frame(640, 480)
        frame_code.draw(frame, 57)
        self.assertIsNone(frame_code.read(lambda x, y: frame.luma(1 - x - 1e-9, y)))

    def test_a_damaged_code_reads_as_none(self) -> None:
        frame = _Frame(640, 480)
        frame_code.draw(frame, 57)
        frame[450:480, 32 * 17 : 32 * 18] = 0  # the last bit of the number, a 1, blacked out
        self.assertIsNone(frame_code.read(frame.luma))

    def test_a_number_that_does_not_fit_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            frame_code.cells(1 << 16)


if __name__ == "__main__":
    unittest.main()

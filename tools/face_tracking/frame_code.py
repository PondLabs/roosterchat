"""The frame code burned into the face tracking test videos.

A strip across the bottom sixteenth of the frame, cut into 20 equal cells,
read left to right: white, black, the 16 bits of the frame number (most
significant first, white is 1), an even parity bit, black. A tracker reads
it from the very pixels it analysed, so an anchor can be compared with the
reference of the same frame whatever the delay in between
(docs/adr/0006-face-tracking.md).
"""

from __future__ import annotations

from typing import Callable

CELLS = 20
STRIP = 1 / 16
CENTRE_Y = 1 - STRIP / 2
_MIN_CONTRAST = 64


def cells(code: int) -> list[int]:
    """The 20 cells of a frame code, 1 for white."""
    if not 0 <= code < 1 << 16:
        raise ValueError(f"frame code out of range: {code}")
    bits = [(code >> shift) & 1 for shift in range(15, -1, -1)]
    return [1, 0, *bits, sum(bits) & 1, 0]


def read(luma: Callable[[float, float], float]) -> int | None:
    """Reads the code from a frame.

    `luma(x, y)` gives the brightness (0 to 255) at a point of the upright
    frame, x and y as fractions of its width and height. None when the frame
    has no code, or the code does not hold together.
    """
    seen = [luma((i + 0.5) / CELLS, CENTRE_Y) for i in range(CELLS)]
    if seen[0] - seen[1] < _MIN_CONTRAST:
        return None
    threshold = (seen[0] + seen[1]) / 2
    bits = [1 if value > threshold else 0 for value in seen]
    code = 0
    for bit in bits[2:18]:
        code = code << 1 | bit
    return code if bits == cells(code) else None


def draw(frame, code: int) -> None:
    """Burns the code into a frame: rows of pixels, `frame[y, x]` settable
    by slices (a numpy image)."""
    height, width = len(frame), len(frame[0])
    top = height - round(height * STRIP)
    for i, bit in enumerate(cells(code)):
        left, right = round(i * width / CELLS), round((i + 1) * width / CELLS)
        frame[top:height, left:right] = 255 if bit else 0

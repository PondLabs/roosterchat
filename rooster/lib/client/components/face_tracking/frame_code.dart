/// The frame code burned into the test videos (tools/face_tracking/
/// frame_code.py): a strip across the bottom sixteenth of the frame in 20
/// cells, white, black, the 16 bits of the frame number (most significant
/// first, white is 1), an even parity bit, black.
const frameCodeCells = 20;

/// Where the cells are read, as a fraction of the frame's height: the
/// middle of the strip.
const frameCodeRow = 1 - 1 / 32;

/// The frame number from the brightness (0 to 255) of the middle of each of
/// the [frameCodeCells] cells, left to right; null when the frame has no
/// code or it does not hold together.
int? readFrameCode(List<double> cells) {
  if (cells.length != frameCodeCells || cells[0] - cells[1] < 64) return null;
  final threshold = (cells[0] + cells[1]) / 2;
  final bits = [for (final cell in cells) cell > threshold ? 1 : 0];
  var code = 0, ones = 0;
  for (final bit in bits.sublist(2, 18)) {
    code = code << 1 | bit;
    ones += bit;
  }
  return bits[18] == ones & 1 && bits[19] == 0 ? code : null;
}

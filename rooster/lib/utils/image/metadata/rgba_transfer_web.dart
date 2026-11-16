import 'dart:typed_data';

/// On the web `compute` runs the work on the same thread: nothing crosses
/// into an isolate, so the pixels are kept as they are.
class PackedRgba {
  PackedRgba(this.payload);

  final Uint8List payload;

  Uint8List unpack() => payload;
}
